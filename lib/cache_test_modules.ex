if System.get_env("IS_CI") === "true" do
  defmodule TestCache.Redis do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: [uri: "redis://localhost:6379"]
  end

  defmodule TestCache.ETS do
    use Cache,
      adapter: Cache.ETS,
      name: :test_cache_ets,
      opts: []
  end

  defmodule TestCache.DETS do
    use Cache,
      adapter: Cache.DETS,
      name: :test_cache_dets,
      opts: []
  end

  defmodule TestCache.DirtyConCache do
    use Cache,
      adapter: Cache.ConCache,
      name: :test_cache_dirty_con_cache,
      opts: []
  end

  defmodule TestCache.ConCache do
    use Cache,
      adapter: Cache.ConCache,
      name: :test_cache_con_cache,
      opts: [dirty?: false]
  end

  defmodule TestCache.Agent do
    use Cache,
      adapter: Cache.Agent,
      name: :test_cache_agent,
      opts: []
  end

  defmodule TestCache.Counter do
    use Cache,
      adapter: Cache.Counter,
      name: :test_cache_counter,
      opts: [initial_size: 100_000_000]
  end

  defmodule TestCache.PersistentTerm do
    use Cache,
      adapter: Cache.PersistentTerm,
      name: :test_cache_persistent_term,
      opts: []
  end

  defmodule TestCache.RefreshAheadETS do
    use Cache,
      adapter: {Cache.RefreshAhead, Cache.ETS},
      name: :test_strategy_refresh_ahead_ets,
      opts: [refresh_before: 500]

    def refresh(key), do: {:ok, "refreshed:#{key}"}
  end

  defmodule TestCache.HashRingETS do
    use Cache,
      adapter: {Cache.HashRing, Cache.ETS},
      name: :test_strategy_hash_ring_ets,
      opts: []
  end

  defmodule TestCache.MultiLayerETS do
    use Cache,
      adapter: {Cache.MultiLayer, [Cache.ETS, Cache.Agent]},
      name: :test_strategy_multi_layer_ets,
      opts: []
  end

  defmodule TestCache.Layer1 do
    use Cache,
      adapter: Cache.ETS,
      name: :test_multi_layer_layer1,
      opts: []
  end

  defmodule TestCache.Layer2 do
    use Cache,
      adapter: Cache.Agent,
      name: :test_multi_layer_layer2,
      opts: []
  end

  defmodule TestCache.MultiLayerModules do
    use Cache,
      adapter: {Cache.MultiLayer, [TestCache.Layer1, TestCache.Layer2]},
      name: :test_strategy_multi_layer_modules,
      opts: []
  end

  defmodule TestCache.MultiLayerFetch do
    use Cache,
      adapter: {Cache.MultiLayer, [Cache.ETS]},
      name: :test_strategy_multi_layer_fetch,
      opts: [on_fetch: &__MODULE__.fetch/1]

    def fetch(key), do: {:ok, "fetched:#{key}"}
  end
end
