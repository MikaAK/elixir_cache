defmodule Cache.HashRing.RingMonitorTest do
  use ExUnit.Case, async: true

  alias Cache.HashRing.RingMonitor

  describe "history_table_name/1" do
    test "returns the expected atom" do
      assert RingMonitor.history_table_name(:my_cache) === :my_cache_ring_history
    end
  end

  describe "previous_rings/1" do
    test "returns empty list when table does not exist" do
      assert RingMonitor.previous_rings(:nonexistent_cache) === []
    end

    test "returns empty list when table exists but has no rings stored" do
      table_name = :"monitor_test_#{System.unique_integer([:positive])}_ring_history"
      :ets.new(table_name, [:set, :public, :named_table])
      :ets.insert(table_name, {:previous_rings, []})

      cache_name = String.to_atom(String.replace(to_string(table_name), "_ring_history", ""))
      assert RingMonitor.previous_rings(cache_name) === []

      :ets.delete(table_name)
    end

    test "returns stored rings" do
      table_name = :"ring_stored_test_#{System.unique_integer([:positive])}_ring_history"
      :ets.new(table_name, [:set, :public, :named_table])
      fake_rings = [:ring1, :ring2]
      :ets.insert(table_name, {:previous_rings, fake_rings})

      cache_name = String.to_atom(String.replace(to_string(table_name), "_ring_history", ""))
      assert RingMonitor.previous_rings(cache_name) === fake_rings

      :ets.delete(table_name)
    end
  end

  describe "init/1" do
    test "creates ETS history table and monitors nodes" do
      cache_name = :"ring_init_test_#{System.unique_integer([:positive])}"
      ring_name = :"#{cache_name}_hash_ring"

      pid =
        start_supervised!(%{
          id: cache_name,
          start: {RingMonitor, :start_link, [[cache_name: cache_name, ring_name: ring_name, history_size: 3]]}
        })

      table = RingMonitor.history_table_name(cache_name)
      assert :ets.whereis(table) !== :undefined
      assert RingMonitor.previous_rings(cache_name) === []
      assert Process.alive?(pid)
    end
  end

  describe "handle_info/2" do
    test "ignores unrelated messages" do
      cache_name = :"ring_info_test_#{System.unique_integer([:positive])}"
      ring_name = :"#{cache_name}_hash_ring"

      pid =
        start_supervised!(%{
          id: cache_name,
          start: {RingMonitor, :start_link, [[cache_name: cache_name, ring_name: ring_name, history_size: 3]]}
        })

      send(pid, :some_random_message)
      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "handles nodeup/nodedown events without crashing" do
      cache_name = :"ring_nodeup_test_#{System.unique_integer([:positive])}"
      ring_name = :"#{cache_name}_hash_ring"

      pid =
        start_supervised!(%{
          id: cache_name,
          start: {RingMonitor, :start_link, [[cache_name: cache_name, ring_name: ring_name, history_size: 3]]}
        })

      send(pid, {:nodeup, :"fake@node", %{}})
      Process.sleep(50)
      assert Process.alive?(pid)

      send(pid, {:nodedown, :"fake@node", %{}})
      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end
end
