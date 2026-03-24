defmodule Cache.RefreshAheadTest do
  use ExUnit.Case, async: true

  defmodule TestRefreshCache do
    use Cache,
      adapter: {Cache.RefreshAhead, Cache.ETS},
      name: :test_refresh_cache,
      opts: [refresh_before: 500]

    def refresh(key), do: {:ok, "refreshed:#{key}"}
  end

  defmodule CallbackRefreshCache do
    use Cache,
      adapter: {Cache.RefreshAhead, Cache.ETS},
      name: :callback_refresh_cache,
      opts: [
        refresh_before: 500,
        on_refresh: &__MODULE__.custom_refresh/1
      ]

    def custom_refresh(key), do: {:ok, "custom:#{key}"}
  end

  defmodule LockedRefreshCache do
    use Cache,
      adapter: {Cache.RefreshAhead, Cache.ETS},
      name: :locked_refresh_cache,
      opts: [
        refresh_before: 500,
        lock_node_whitelist: [node()]
      ]

    def refresh(key), do: {:ok, "locked:#{key}"}
  end

  setup do
    start_supervised!(%{
      id: :refresh_cache_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[TestRefreshCache], [name: :refresh_cache_sup]]}
    })

    start_supervised!(%{
      id: :callback_refresh_cache_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[CallbackRefreshCache], [name: :callback_refresh_cache_sup]]}
    })

    start_supervised!(%{
      id: :locked_refresh_cache_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[LockedRefreshCache], [name: :locked_refresh_cache_sup]]}
    })

    :ok
  end

  describe "put/3 and get/1 - basic operations" do
    test "stores and retrieves a value" do
      assert :ok === TestRefreshCache.put("basic_key", 10_000, "hello")
      assert {:ok, "hello"} === TestRefreshCache.get("basic_key")
    end

    test "returns nil for missing keys" do
      assert {:ok, nil} === TestRefreshCache.get("missing_key")
    end

    test "stores complex values" do
      assert :ok === TestRefreshCache.put("map_key", 10_000, %{a: 1, b: 2})
      assert {:ok, %{a: 1, b: 2}} === TestRefreshCache.get("map_key")
    end
  end

  describe "delete/1" do
    test "removes a stored value" do
      assert :ok === TestRefreshCache.put("delete_key", 10_000, "to_delete")
      assert {:ok, "to_delete"} === TestRefreshCache.get("delete_key")
      assert :ok === TestRefreshCache.delete("delete_key")
      assert {:ok, nil} === TestRefreshCache.get("delete_key")
    end
  end

  describe "refresh-ahead behaviour" do
    test "does not trigger refresh when far from TTL expiry" do
      assert :ok === TestRefreshCache.put("no_refresh_key", 10_000, "original")

      assert {:ok, "original"} === TestRefreshCache.get("no_refresh_key")

      Process.sleep(50)

      assert {:ok, "original"} === TestRefreshCache.get("no_refresh_key")
    end

    test "triggers async refresh when within refresh_before window" do
      assert :ok === TestRefreshCache.put("refresh_key", 2000, "original")

      assert {:ok, "original"} === TestRefreshCache.get("refresh_key")

      Process.sleep(1600)

      assert {:ok, "original"} === TestRefreshCache.get("refresh_key")

      Process.sleep(200)

      assert {:ok, "refreshed:refresh_key"} === TestRefreshCache.get("refresh_key")
    end

    test "on_refresh option overrides module callback" do
      assert :ok === CallbackRefreshCache.put("cb_key", 2000, "original")

      assert {:ok, "original"} === CallbackRefreshCache.get("cb_key")

      Process.sleep(1600)

      assert {:ok, "original"} === CallbackRefreshCache.get("cb_key")

      Process.sleep(200)

      assert {:ok, "custom:cb_key"} === CallbackRefreshCache.get("cb_key")
    end
  end

  describe "deduplication" do
    test "multiple concurrent gets only spawn one refresh task" do
      assert :ok === TestRefreshCache.put("dedup_key", 2000, "original")

      Process.sleep(1600)

      tasks =
        Enum.map(1..5, fn _ ->
          Task.async(fn -> TestRefreshCache.get("dedup_key") end)
        end)

      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, val} -> val === "original" end)

      Process.sleep(200)

      assert {:ok, "refreshed:dedup_key"} === TestRefreshCache.get("dedup_key")
    end

    test "global lock prevents refresh while lock is held" do
      lock_resource = {:refresh_ahead_lock, :locked_refresh_cache, "locked_key"}
      lock_id = {lock_resource, self()}
      lock_nodes = [Node.self()]

      assert true === :global.set_lock(lock_id, lock_nodes, 0)
      assert :ok === LockedRefreshCache.put("locked_key", 2000, "original")

      Process.sleep(1600)

      assert {:ok, "original"} === LockedRefreshCache.get("locked_key")

      Process.sleep(250)

      assert {:ok, "original"} === LockedRefreshCache.get("locked_key")
      assert true === :global.del_lock(lock_id, lock_nodes)

      assert {:ok, "original"} === LockedRefreshCache.get("locked_key")

      Process.sleep(250)

      assert {:ok, "locked:locked_key"} === LockedRefreshCache.get("locked_key")
    end
  end

  describe "MFA-style on_refresh callback" do
    defmodule MFARefreshHelper do
      def refresh(key), do: {:ok, "mfa:#{key}"}
    end

    defmodule MFARefreshCache do
      use Cache,
        adapter: {Cache.RefreshAhead, Cache.ETS},
        name: :mfa_refresh_cache,
        opts: [
          refresh_before: 500,
          on_refresh: {Cache.RefreshAheadTest.MFARefreshHelper, :refresh, []}
        ]
    end

    setup do
      start_supervised!(%{
        id: :mfa_refresh_cache_sup,
        type: :supervisor,
        start: {Cache, :start_link, [[MFARefreshCache], [name: :mfa_refresh_cache_sup]]}
      })

      :ok
    end

    test "uses MFA tuple for refresh callback" do
      assert :ok === MFARefreshCache.put("mfa_key", 2000, "original")
      assert {:ok, "original"} === MFARefreshCache.get("mfa_key")

      Process.sleep(1600)

      assert {:ok, "original"} === MFARefreshCache.get("mfa_key")

      Process.sleep(200)

      assert {:ok, "mfa:mfa_key"} === MFARefreshCache.get("mfa_key")
    end
  end

  describe "put without TTL" do
    test "stores value without refresh wrapper when TTL is nil" do
      assert :ok === TestRefreshCache.put("no_ttl_key", "value")
      assert {:ok, "value"} === TestRefreshCache.get("no_ttl_key")
    end
  end

  describe "lock_node_whitelist with atom" do
    defmodule AtomWhitelistCache do
      use Cache,
        adapter: {Cache.RefreshAhead, Cache.ETS},
        name: :atom_whitelist_cache,
        opts: [
          refresh_before: 500,
          lock_node_whitelist: :nonode@nohost
        ]

      def refresh(key), do: {:ok, "atom_wl:#{key}"}
    end

    setup do
      start_supervised!(%{
        id: :atom_whitelist_cache_sup,
        type: :supervisor,
        start: {Cache, :start_link, [[AtomWhitelistCache], [name: :atom_whitelist_cache_sup]]}
      })

      :ok
    end

    test "works with atom whitelist" do
      assert :ok === AtomWhitelistCache.put("awl_key", 2000, "original")

      Process.sleep(1600)

      assert {:ok, "original"} === AtomWhitelistCache.get("awl_key")

      Process.sleep(200)

      assert {:ok, "atom_wl:awl_key"} === AtomWhitelistCache.get("awl_key")
    end
  end

  describe "cache_adapter/0" do
    test "returns Cache.RefreshAhead as adapter" do
      assert TestRefreshCache.cache_adapter() === Cache.RefreshAhead
    end
  end

  describe "Cache.Strategy.strategy?/1" do
    test "recognises Cache.RefreshAhead as a strategy" do
      assert Cache.Strategy.strategy?(Cache.RefreshAhead) === true
    end
  end
end
