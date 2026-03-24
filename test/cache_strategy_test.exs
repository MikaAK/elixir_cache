defmodule CacheStrategyTest do
  use ExUnit.Case, async: true

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

  @strategy_adapters [
    TestCache.RefreshAheadETS,
    TestCache.HashRingETS,
    TestCache.MultiLayerModules
  ]

  for adapter <- @strategy_adapters do
    describe "#{adapter} &get/1 & &put/2 & &delete/1" do
      setup do
        start_supervised!(%{
          id: :"#{unquote(adapter)}_sup",
          type: :supervisor,
          start:
            {Cache, :start_link,
             [
               [TestCache.Layer1, TestCache.Layer2, unquote(adapter)],
               [name: :"#{unquote(adapter)}_sup"]
             ]}
        })

        Process.sleep(50)

        :ok
      end

      test "puts into the cache and can get it back after" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = unquote(adapter)

        assert {:ok, nil} = cache_module.get(test_key)
        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert {:ok, value} === cache_module.get(test_key)
      end

      test "deleting from cache works" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = unquote(adapter)

        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert :ok = cache_module.delete(test_key)

        Process.sleep(50)

        assert {:ok, nil} = cache_module.get(test_key)
      end

      test "puts into the cache with nil acts like deleting" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = unquote(adapter)

        assert {:ok, nil} = cache_module.get(test_key)
        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert {:ok, value} === cache_module.get(test_key)
        assert :ok = cache_module.put(test_key, nil)

        Process.sleep(50)

        assert {:ok, nil} = cache_module.get(test_key)
      end
    end

    describe "#{adapter} &get_or_create/2" do
      setup do
        start_supervised!(%{
          id: :"#{unquote(adapter)}_get_or_create_sup",
          type: :supervisor,
          start:
            {Cache, :start_link,
             [
               [TestCache.Layer1, TestCache.Layer2, unquote(adapter)],
               [name: :"#{unquote(adapter)}_get_or_create_sup"]
             ]}
        })

        Process.sleep(50)

        :ok
      end

      test "finds an item in the cache that already exists" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = unquote(adapter)

        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert {:ok, value} ===
                 cache_module.get_or_create(test_key, fn ->
                   raise "I shouldn't be called"
                 end)

        assert {:ok, value} === cache_module.get(test_key)
      end

      test "creates a value for key when key doesn't exist in cache" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = unquote(adapter)

        assert {:ok, nil} = cache_module.get(test_key)

        assert {:ok, value} ===
                 cache_module.get_or_create(test_key, fn ->
                   {:ok, value}
                 end)

        Process.sleep(50)

        assert {:ok, value} === cache_module.get(test_key)
      end
    end
  end

  describe "&cache_adapter/0" do
    test "returns the strategy module for RefreshAhead" do
      assert TestCache.RefreshAheadETS.cache_adapter() === Cache.RefreshAhead
    end

    test "returns the strategy module for HashRing" do
      assert TestCache.HashRingETS.cache_adapter() === Cache.HashRing
    end

    test "returns the strategy module for MultiLayer" do
      assert TestCache.MultiLayerETS.cache_adapter() === Cache.MultiLayer
    end
  end

  describe "Cache.Strategy.strategy?/1" do
    test "returns true for Cache.RefreshAhead" do
      assert Cache.Strategy.strategy?(Cache.RefreshAhead) === true
    end

    test "returns true for Cache.HashRing" do
      assert Cache.Strategy.strategy?(Cache.HashRing) === true
    end

    test "returns true for Cache.MultiLayer" do
      assert Cache.Strategy.strategy?(Cache.MultiLayer) === true
    end

    test "returns false for plain adapters" do
      refute Cache.Strategy.strategy?(Cache.ETS)
      refute Cache.Strategy.strategy?(Cache.Agent)
      refute Cache.Strategy.strategy?(Cache.Redis)
    end

    test "returns false for non-existent module" do
      refute Cache.Strategy.strategy?(NonExistentModule)
    end

    test "returns false for non-module term" do
      refute Cache.Strategy.strategy?(:not_a_real_module_at_all)
    end
  end

  describe "Cache.MultiLayer layered read behaviour" do
    setup do
      start_supervised!(%{
        id: :multi_layer_modules_sup,
        type: :supervisor,
        start:
          {Cache, :start_link,
           [
             [TestCache.Layer1, TestCache.Layer2, TestCache.MultiLayerModules],
             [name: :multi_layer_modules_sup]
           ]}
      })

      Process.sleep(50)

      :ok
    end

    test "reads from layer1 first when value is present" do
      key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
      TestCache.Layer1.put(key, "from_layer1")

      assert {:ok, "from_layer1"} === TestCache.MultiLayerModules.get(key)
    end

    test "falls through to layer2 when layer1 misses" do
      key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
      TestCache.Layer2.put(key, "from_layer2")

      assert {:ok, "from_layer2"} === TestCache.MultiLayerModules.get(key)
    end

    test "backfills layer1 after a hit in layer2" do
      key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
      TestCache.Layer2.put(key, "from_layer2")

      assert {:ok, "from_layer2"} === TestCache.MultiLayerModules.get(key)

      assert {:ok, "from_layer2"} === TestCache.Layer1.get(key)
    end

    test "returns nil when all layers miss" do
      key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"

      assert {:ok, nil} === TestCache.MultiLayerModules.get(key)
    end
  end

  describe "Cache.MultiLayer write behaviour" do
    setup do
      start_supervised!(%{
        id: :multi_layer_write_sup,
        type: :supervisor,
        start:
          {Cache, :start_link,
           [
             [TestCache.Layer1, TestCache.Layer2, TestCache.MultiLayerModules],
             [name: :multi_layer_write_sup]
           ]}
      })

      Process.sleep(50)

      :ok
    end

    test "put writes to all layers" do
      key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"

      assert :ok = TestCache.MultiLayerModules.put(key, "value")

      assert {:ok, "value"} === TestCache.Layer1.get(key)
      assert {:ok, "value"} === TestCache.Layer2.get(key)
    end

    test "delete removes from all layers" do
      key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"

      TestCache.MultiLayerModules.put(key, "value")
      assert :ok = TestCache.MultiLayerModules.delete(key)

      assert {:ok, nil} === TestCache.Layer1.get(key)
      assert {:ok, nil} === TestCache.Layer2.get(key)
    end
  end

  describe "Cache.MultiLayer on_fetch callback" do
    setup do
      start_supervised!(%{
        id: :multi_layer_fetch_sup,
        type: :supervisor,
        start:
          {Cache, :start_link,
           [[TestCache.MultiLayerFetch], [name: :multi_layer_fetch_sup]]}
      })

      Process.sleep(50)

      :ok
    end

    test "invokes fetch callback on total miss and backfills layers" do
      key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"

      assert {:ok, "fetched:#{key}"} === TestCache.MultiLayerFetch.get(key)

      assert {:ok, "fetched:#{key}"} === TestCache.MultiLayerFetch.get(key)
    end
  end
end
