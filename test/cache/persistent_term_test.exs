defmodule Cache.PersistentTermTest do
  use ExUnit.Case, async: true

  defmodule TestPersistentTermCache do
    use Cache,
      adapter: Cache.PersistentTerm,
      name: :test_persistent_term_cache,
      opts: []
  end

  setup do
    start_supervised({Cache, [TestPersistentTermCache]})

    on_exit(fn ->
      :persistent_term.erase({:test_persistent_term_cache, :cleanup_key})
    end)

    :ok
  end

  describe "put/3 and get/1" do
    test "stores and retrieves a value" do
      assert :ok === TestPersistentTermCache.put(:my_key, "hello")
      assert {:ok, "hello"} === TestPersistentTermCache.get(:my_key)
    end

    test "returns nil for unknown key" do
      assert {:ok, nil} === TestPersistentTermCache.get(:nonexistent_key)
    end

    test "overwrites an existing value" do
      assert :ok === TestPersistentTermCache.put(:overwrite_key, "first")
      assert :ok === TestPersistentTermCache.put(:overwrite_key, "second")
      assert {:ok, "second"} === TestPersistentTermCache.get(:overwrite_key)
    end

    test "stores complex terms" do
      value = %{nested: [1, 2, 3], map: %{a: :b}}
      assert :ok === TestPersistentTermCache.put(:complex_key, value)
      assert {:ok, ^value} = TestPersistentTermCache.get(:complex_key)
    end

    test "ttl argument is ignored" do
      assert :ok === TestPersistentTermCache.put(:ttl_key, 1000, "still stored")
      assert {:ok, "still stored"} === TestPersistentTermCache.get(:ttl_key)
    end
  end

  describe "delete/1" do
    test "removes an existing key" do
      assert :ok === TestPersistentTermCache.put(:delete_key, "value")
      assert :ok === TestPersistentTermCache.delete(:delete_key)
      assert {:ok, nil} === TestPersistentTermCache.get(:delete_key)
    end

    test "is a no-op for non-existent key" do
      assert :ok === TestPersistentTermCache.delete(:never_set_key)
    end
  end
end
