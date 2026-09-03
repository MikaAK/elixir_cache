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

  # Every fixture cache uses refresh_before: 500, so this TTL is inside the window at age 0.
  @in_window_ttl 500

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
      assert {:ok, "original"} === TestRefreshCache.get("no_refresh_key")
    end

    # A TTL no larger than refresh_before puts the key inside the refresh window from the
    # first read: that read returns the stale value and spawns the async refresh.
    test "triggers async refresh when within refresh_before window" do
      assert :ok === TestRefreshCache.put("refresh_key", @in_window_ttl, "original")

      assert {:ok, "original"} === TestRefreshCache.get("refresh_key")

      assert Cache.Wait.until(fn ->
               TestRefreshCache.get("refresh_key") === {:ok, "refreshed:refresh_key"}
             end)
    end

    test "on_refresh option overrides module callback" do
      assert :ok === CallbackRefreshCache.put("cb_key", @in_window_ttl, "original")

      assert {:ok, "original"} === CallbackRefreshCache.get("cb_key")

      assert Cache.Wait.until(fn ->
               CallbackRefreshCache.get("cb_key") === {:ok, "custom:cb_key"}
             end)
    end
  end

  describe "deduplication" do
    # The refresh callback counts its calls and then blocks until the test opens the gate,
    # so every concurrent get runs while one refresh is provably still in flight.
    defmodule DedupRefreshCache do
      use Cache,
        adapter: {Cache.RefreshAhead, Cache.ETS},
        name: :dedup_refresh_cache,
        opts: [refresh_before: 500]

      def refresh(key) do
        Agent.update(__MODULE__.Calls, &(&1 + 1))
        Cache.Wait.until(fn -> Agent.get(__MODULE__.Gate, & &1) end, 5_000)
        {:ok, "refreshed:#{key}"}
      end
    end

    setup do
      start_supervised!(%{
        id: :dedup_refresh_cache_sup,
        type: :supervisor,
        start: {Cache, :start_link, [[DedupRefreshCache], [name: :dedup_refresh_cache_sup]]}
      })

      start_supervised!(%{id: :calls, start: {Agent, :start_link, [fn -> 0 end, [name: DedupRefreshCache.Calls]]}})
      start_supervised!(%{id: :gate, start: {Agent, :start_link, [fn -> false end, [name: DedupRefreshCache.Gate]]}})

      :ok
    end

    test "multiple concurrent gets only spawn one refresh task" do
      assert :ok === DedupRefreshCache.put("dedup_key", @in_window_ttl, "original")

      results =
        1..5
        |> Enum.map(fn _ -> Task.async(fn -> DedupRefreshCache.get("dedup_key") end) end)
        |> Task.await_many()

      assert Enum.all?(results, &(&1 === {:ok, "original"}))

      # The one refresh task is parked at the gate, so the count cannot climb past 1.
      assert Cache.Wait.until(fn -> Agent.get(DedupRefreshCache.Calls, & &1) >= 1 end)
      assert Agent.get(DedupRefreshCache.Calls, & &1) === 1

      Agent.update(DedupRefreshCache.Gate, fn _ -> true end)

      assert Cache.Wait.until(fn ->
               DedupRefreshCache.get("dedup_key") === {:ok, "refreshed:dedup_key"}
             end)
    end

    test "global lock prevents refresh while lock is held" do
      lock_resource = {:refresh_ahead_lock, :locked_refresh_cache, "locked_key"}
      lock_id = {lock_resource, self()}
      lock_nodes = [Node.self()]

      assert true === :global.set_lock(lock_id, lock_nodes, 0)
      assert :ok === LockedRefreshCache.put("locked_key", @in_window_ttl, "original")

      assert {:ok, "original"} === LockedRefreshCache.get("locked_key")
      assert Cache.Wait.until(fn -> refresh_finished?(:locked_refresh_cache, "locked_key") end)

      assert {:ok, "original"} === LockedRefreshCache.get("locked_key")

      # That get spawned a refresh task. Wait for it to lose the race for the lock and
      # clean itself up before releasing — otherwise it can reach :global.set_lock after
      # the del_lock below, take the freed lock, and refresh the value we assert is still
      # untouched.
      assert Cache.Wait.until(fn -> refresh_finished?(:locked_refresh_cache, "locked_key") end)

      assert true === :global.del_lock(lock_id, lock_nodes)

      assert {:ok, "original"} === LockedRefreshCache.get("locked_key")

      assert Cache.Wait.until(fn ->
               LockedRefreshCache.get("locked_key") === {:ok, "locked:locked_key"}
             end)
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
      assert :ok === MFARefreshCache.put("mfa_key", @in_window_ttl, "original")
      assert {:ok, "original"} === MFARefreshCache.get("mfa_key")

      assert Cache.Wait.until(fn -> MFARefreshCache.get("mfa_key") === {:ok, "mfa:mfa_key"} end)
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
      assert :ok === AtomWhitelistCache.put("awl_key", @in_window_ttl, "original")

      assert {:ok, "original"} === AtomWhitelistCache.get("awl_key")

      assert Cache.Wait.until(fn ->
               AtomWhitelistCache.get("awl_key") === {:ok, "atom_wl:awl_key"}
             end)
    end
  end

  # The refresh task clears its tracker entry in an `after` block, so an absent entry means
  # the spawned task has finished — whether it refreshed or lost the lock race.
  defp refresh_finished?(cache_name, key) do
    not :ets.member(:"#{cache_name}_refresh_tracker", key)
  end

  describe "strategy calls on a cache whose tracker table does not exist" do
    test "get/4 still returns the stored value and skips the refresh" do
      :ets.new(:orphan_refresh_cache, [:set, :public, :named_table])
      wrapped = {"original", System.monotonic_time(:millisecond), @in_window_ttl}
      :ets.insert(:orphan_refresh_cache, {"key", wrapped})

      assert {:ok, "original"} ===
               Cache.RefreshAhead.get(:orphan_refresh_cache, "key", Cache.ETS, refresh_before: 500)
    end

    test "delete/4 returns the underlying adapter's error instead of raising" do
      assert {:error, %ErrorMessage{code: :internal_server_error}} =
               Cache.RefreshAhead.delete(:no_such_refresh_cache, "key", Cache.ETS, [])
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
