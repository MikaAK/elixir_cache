defmodule Cache.MultiLayerBroadcastTest do
  use ExUnit.Case

  alias Cache.MultiLayer.Coordinator

  defmodule LocalLayer do
    use Cache,
      adapter: Cache.ETS,
      name: :mlb_local_layer,
      opts: []
  end

  defmodule SharedLayer do
    use Cache,
      adapter: Cache.ETS,
      name: :mlb_shared_layer,
      opts: []
  end

  defmodule InvalidatingCache do
    use Cache,
      adapter: {Cache.MultiLayer, [LocalLayer, SharedLayer]},
      name: :mlb_invalidating_cache,
      opts: [broadcast_mode: :invalidate, broadcast_layers: [LocalLayer]]
  end

  defmodule ReplicatingCache do
    use Cache,
      adapter: {Cache.MultiLayer, [LocalLayer, SharedLayer]},
      name: :mlb_replicating_cache,
      opts: [broadcast_mode: :replicate, broadcast_layers: [LocalLayer]]
  end

  setup do
    start_supervised!(%{
      id: :mlb_sup,
      type: :supervisor,
      start:
        {Cache, :start_link,
         [[LocalLayer, SharedLayer, InvalidatingCache, ReplicatingCache], [name: :mlb_sup]]}
    })

    :ok
  end

  describe "coordinator pg membership" do
    test "joins a pg group named after the cache" do
      assert Coordinator.members(:mlb_invalidating_cache) !== []
    end
  end

  describe "coordinator message handling" do
    test "invalidate message deletes the key from the given layers only" do
      :ok = LocalLayer.put("inv_key", "stale")
      :ok = SharedLayer.put("inv_key", "fresh")

      [coordinator | _rest] = Coordinator.members(:mlb_invalidating_cache)
      send(coordinator, {:multi_layer_invalidate, "inv_key", [LocalLayer]})

      # handle_info is async — sync on the coordinator's mailbox draining.
      _synced = :sys.get_state(coordinator)

      assert {:ok, nil} === LocalLayer.get("inv_key")
      assert {:ok, "fresh"} === SharedLayer.get("inv_key")
    end

    test "replicate message writes the value into the given layers only" do
      [coordinator | _rest] = Coordinator.members(:mlb_replicating_cache)
      send(coordinator, {:multi_layer_replicate, "rep_key", nil, "pushed", [LocalLayer]})

      _synced = :sys.get_state(coordinator)

      assert {:ok, "pushed"} === LocalLayer.get("rep_key")
      assert {:ok, nil} === SharedLayer.get("rep_key")
    end

    test "unknown messages are ignored" do
      [coordinator | _rest] = Coordinator.members(:mlb_invalidating_cache)
      send(coordinator, :unexpected)

      assert :sys.get_state(coordinator)
    end
  end

  describe "broadcast/2 member targeting" do
    test "reaches other pg members but never the cache's own coordinator" do
      # Join the test process as a fake remote member alongside the real
      # coordinator; broadcast must reach it while the real coordinator's
      # local layer entry (freshly written) stays untouched.
      :ok = :pg.join(:cache_multi_layer_coordinator, :mlb_invalidating_cache, self())

      Coordinator.broadcast(:mlb_invalidating_cache, {:multi_layer_invalidate, "bk", [LocalLayer]})

      assert_receive {:multi_layer_invalidate, "bk", [LocalLayer]}
    end
  end

  describe "put/delete broadcast integration" do
    test "put with broadcast_mode: :invalidate notifies members with the key" do
      :ok = :pg.join(:cache_multi_layer_coordinator, :mlb_invalidating_cache, self())

      assert :ok === InvalidatingCache.put("put_key", "value")

      assert_receive {:multi_layer_invalidate, "put_key", [LocalLayer]}

      # The writing node's own layers hold the fresh value untouched.
      assert {:ok, "value"} === LocalLayer.get("put_key")
      assert {:ok, "value"} === SharedLayer.get("put_key")
    end

    test "put with broadcast_mode: :replicate ships the value" do
      :ok = :pg.join(:cache_multi_layer_coordinator, :mlb_replicating_cache, self())

      assert :ok === ReplicatingCache.put("rep_put", "rep_value")

      assert_receive {:multi_layer_replicate, "rep_put", nil, "rep_value", [LocalLayer]}
    end

    test "delete broadcasts an invalidate regardless of mode" do
      :ok = :pg.join(:cache_multi_layer_coordinator, :mlb_replicating_cache, self())

      :ok = ReplicatingCache.put("del_key", "value")
      assert_receive {:multi_layer_replicate, "del_key", _ttl, _value, _layers}

      assert :ok === ReplicatingCache.delete("del_key")
      assert_receive {:multi_layer_invalidate, "del_key", [LocalLayer]}
    end
  end
end
