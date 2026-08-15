defmodule Cache.HashRingTest do
  use ExUnit.Case, async: true

  defmodule TestHashRingCache do
    use Cache,
      adapter: {Cache.HashRing, Cache.ETS},
      name: :test_hash_ring_cache,
      opts: []
  end

  setup do
    start_supervised!(%{
      id: :hash_ring_cache_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[TestHashRingCache], [name: :hash_ring_cache_sup]]}
    })

    Process.sleep(50)

    :ok
  end

  describe "put/3 and get/1" do
    test "stores and retrieves a value" do
      assert :ok === TestHashRingCache.put("user:1", "Alice")
      assert {:ok, "Alice"} === TestHashRingCache.get("user:1")
    end

    test "returns nil for missing keys" do
      assert {:ok, nil} === TestHashRingCache.get("missing:key")
    end

    test "stores and retrieves different value types" do
      assert :ok === TestHashRingCache.put("map_key", %{name: "Bob", age: 30})
      assert {:ok, %{name: "Bob", age: 30}} === TestHashRingCache.get("map_key")

      assert :ok === TestHashRingCache.put("list_key", [1, 2, 3])
      assert {:ok, [1, 2, 3]} === TestHashRingCache.get("list_key")
    end

    test "overwrites existing values" do
      assert :ok === TestHashRingCache.put("overwrite_key", "first")
      assert :ok === TestHashRingCache.put("overwrite_key", "second")
      assert {:ok, "second"} === TestHashRingCache.get("overwrite_key")
    end
  end

  describe "delete/1" do
    test "removes a stored value" do
      assert :ok === TestHashRingCache.put("delete_key", "to_delete")
      assert {:ok, "to_delete"} === TestHashRingCache.get("delete_key")
      assert :ok === TestHashRingCache.delete("delete_key")
      assert {:ok, nil} === TestHashRingCache.get("delete_key")
    end

    test "deleting a non-existent key returns ok" do
      assert :ok === TestHashRingCache.delete("nonexistent_key")
    end
  end

  describe "cache_adapter/0" do
    test "returns the strategy module as adapter" do
      assert TestHashRingCache.cache_adapter() === Cache.HashRing
    end
  end

  describe "single-node ring routing" do
    test "routes all keys to Node.self() when single node" do
      assert :ok === TestHashRingCache.put("ring:key1", "val1")
      assert :ok === TestHashRingCache.put("ring:key2", "val2")
      assert :ok === TestHashRingCache.put("ring:key3", "val3")

      assert {:ok, "val1"} === TestHashRingCache.get("ring:key1")
      assert {:ok, "val2"} === TestHashRingCache.get("ring:key2")
      assert {:ok, "val3"} === TestHashRingCache.get("ring:key3")
    end
  end

  describe "get_or_create/2" do
    test "creates value when missing" do
      result =
        TestHashRingCache.get_or_create("create_key", fn ->
          {:ok, "created_value"}
        end)

      assert {:ok, "created_value"} === result
      assert {:ok, "created_value"} === TestHashRingCache.get("create_key")
    end

    test "returns existing value without calling function" do
      TestHashRingCache.put("existing_key", "existing_value")

      result =
        TestHashRingCache.get_or_create("existing_key", fn ->
          raise "should not be called"
        end)

      assert {:ok, "existing_value"} === result
    end
  end

  describe "Cache.Strategy.strategy?/1" do
    test "recognises Cache.HashRing as a strategy" do
      assert Cache.Strategy.strategy?(Cache.HashRing) === true
    end

    test "does not recognise regular adapters as strategies" do
      refute Cache.Strategy.strategy?(Cache.ETS)
      refute Cache.Strategy.strategy?(Cache.Agent)
    end
  end

  describe "read-repair" do
    test "returns nil when no previous rings exist and key is missing" do
      assert {:ok, nil} === TestHashRingCache.get("repair:missing")
    end

    test "skips previous rings where old node equals current node" do
      cache_name = :test_hash_ring_cache

      previous_ring = HashRing.add_node(HashRing.new(), Node.self())
      inject_previous_rings(cache_name, [previous_ring])

      assert {:ok, nil} === TestHashRingCache.get("repair:same_node_key")
    end

    test "skips previous rings where old node is not live" do
      cache_name = :test_hash_ring_cache

      previous_ring = HashRing.add_node(HashRing.new(), :dead_node@nowhere)
      inject_previous_rings(cache_name, [previous_ring])

      assert {:ok, nil} === TestHashRingCache.get("repair:dead_node_key")
    end

    test "deduplicates rpc attempts across ring generations pointing to the same node" do
      cache_name = :test_hash_ring_cache
      fake_node = :fake_dedup@node
      call_count = :"dedup_count_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Agent.start_link(fn -> 0 end, name: call_count)

      rpc_module = build_rpc(fn _node, _mod, _func, _args ->
        Agent.update(call_count, &(&1 + 1))
        {:ok, nil}
      end)

      previous_ring1 = HashRing.add_node(HashRing.new(), fake_node)
      previous_ring2 = HashRing.add_node(HashRing.new(), fake_node)
      inject_previous_rings(cache_name, [previous_ring1, previous_ring2])

      Cache.HashRing.get(cache_name, "repair:dedup_key", Cache.ETS, rpc_module: rpc_module)

      Process.sleep(50)

      assert Agent.get(call_count, & &1) === 1
    end

    test "recovers value via read-repair from old ring owner" do
      cache_name = :test_hash_ring_cache
      fake_node = :fake_live@node
      encoded = Cache.TermEncoder.encode("repaired_value", nil)

      rpc_module = build_rpc(fn node, _mod, func, _args ->
        cond do
          node === fake_node and func === :get -> {:ok, encoded}
          func === :put -> :ok
          func === :delete -> :ok
          true -> {:ok, nil}
        end
      end)

      previous_ring = HashRing.add_node(HashRing.new(), fake_node)
      inject_previous_rings(cache_name, [previous_ring])

      result = Cache.HashRing.get(cache_name, "repair:rpc_key", Cache.ETS, rpc_module: rpc_module)

      assert {:ok, "repaired_value"} === result
    end

    test "migrates value to current node and schedules async delete on repair" do
      cache_name = :test_hash_ring_cache
      fake_node = :fake_migrate@node
      encoded = Cache.TermEncoder.encode("migrate_me", nil)
      calls_agent = :"repair_calls_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Agent.start_link(fn -> [] end, name: calls_agent)

      rpc_module = build_rpc(fn node, _mod, func, _args ->
        Agent.update(calls_agent, fn acc -> [{node, func} | acc] end)

        cond do
          node === fake_node and func === :get -> {:ok, encoded}
          func === :put -> :ok
          func === :delete -> :ok
          true -> {:ok, nil}
        end
      end)

      previous_ring = HashRing.add_node(HashRing.new(), fake_node)
      inject_previous_rings(cache_name, [previous_ring])

      Cache.HashRing.get(cache_name, "repair:migrate_key2", Cache.ETS, rpc_module: rpc_module)

      Process.sleep(100)

      calls = Agent.get(calls_agent, & &1)
      assert Enum.any?(calls, fn {_node, func} -> func === :delete end)
    end
  end

  describe "Cache.HashRing.RingMonitor" do
    test "starts with empty ring history" do
      rings = Cache.HashRing.RingMonitor.previous_rings(:test_hash_ring_cache)
      assert rings === []
    end

    test "previous_rings/1 returns empty list for unknown cache" do
      rings = Cache.HashRing.RingMonitor.previous_rings(:nonexistent_cache)
      assert rings === []
    end

    test "ring_history_size option limits stored snapshots" do
      cache_name = :test_history_size_cache

      defmodule HistorySizeCache do
        use Cache,
          adapter: {Cache.HashRing, Cache.ETS},
          name: :test_history_size_cache,
          opts: [ring_history_size: 2]
      end

      start_supervised!(%{
        id: :history_size_cache_sup,
        type: :supervisor,
        start: {Cache, :start_link, [[HistorySizeCache], [name: :history_size_cache_sup]]}
      })

      ring1 = HashRing.add_node(HashRing.new(), :node1@host)
      ring2 = HashRing.add_node(HashRing.new(), :node2@host)
      ring3 = HashRing.add_node(HashRing.new(), :node3@host)

      inject_previous_rings(cache_name, [ring3, ring2, ring1])

      stored = Cache.HashRing.RingMonitor.previous_rings(cache_name)
      assert length(stored) === 3

      table = Cache.HashRing.RingMonitor.history_table_name(cache_name)
      :ets.insert(table, {:previous_rings, [ring3, ring2, ring1]})
      stored = Cache.HashRing.RingMonitor.previous_rings(cache_name)
      assert length(stored) === 3

      :ets.insert(table, {:previous_rings, Enum.take([ring3, ring2, ring1], 2)})
      stored = Cache.HashRing.RingMonitor.previous_rings(cache_name)
      assert length(stored) === 2
    end
  end

  defp inject_previous_rings(cache_name, rings) do
    table = Cache.HashRing.RingMonitor.history_table_name(cache_name)
    :ets.insert(table, {:previous_rings, rings})
  end

  defp build_rpc(fun) do
    key = {Cache.HashRingTest.StubRpc, self()}
    :persistent_term.put(key, fun)
    on_exit(fn -> :persistent_term.erase(key) end)
    Cache.HashRingTest.StubRpc
  end

  defmodule StubRpc do
    def call(node, mod, func, args) do
      pid = find_registered_pid()

      case pid && :persistent_term.get({Cache.HashRingTest.StubRpc, pid}, nil) do
        nil -> {:ok, nil}
        fun -> fun.(node, mod, func, args)
      end
    end

    defp find_registered_pid do
      callers = Process.get(:"$callers", [])
      ancestors = Process.get(:"$ancestors", [])

      [self() | callers ++ ancestors]
      |> Enum.filter(&is_pid/1)
      |> Enum.find(fn pid ->
        :persistent_term.get({Cache.HashRingTest.StubRpc, pid}, nil) !== nil
      end)
    end
  end
end
