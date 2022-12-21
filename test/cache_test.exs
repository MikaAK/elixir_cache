defmodule CacheTest do
  use ExUnit.Case, async: true

  @adapters [Cache.Redis, Cache.ETS, Cache.Agent]

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

  defmodule TestCache.Agent do
    use Cache,
      adapter: Cache.Agent,
      name: :test_cache_agent,
      opts: []
  end

  for {adapter, adapter_opts} <- @adapters do
    defmodule :"CacheTest.TestCache.#{adapter}" do
    end

    describe "#{adapter} &get/1 & &put/2 & &delete/1" do
      setup do
        start_supervised(
          {Cache,
           [
             :"CacheTest.TestCache.#{unquote(adapter)}"
           ]}
        )

        :ok
      end

      test "puts into the cache and can get it back after" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = :"CacheTest.TestCache.#{unquote(adapter)}"

        assert {:ok, nil} = cache_module.get(test_key)
        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert {:ok, value} === cache_module.get(test_key)
      end

      test "deleteing from cache works" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = :"CacheTest.TestCache.#{unquote(adapter)}"

        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert :ok = cache_module.delete(test_key)

        Process.sleep(50)

        assert {:ok, nil} = cache_module.get(test_key)
      end

      test "puts into the cache with nil acts like deleting" do
        test_key = "#{Faker.Pokemon.name()}_#{Enum.random(1..100_000_000_000)}"
        value = %{some_value: Faker.App.name()}
        cache_module = :"CacheTest.TestCache.#{unquote(adapter)}"

        assert {:ok, nil} = cache_module.get(test_key)
        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert {:ok, value} === cache_module.get(test_key)
        assert :ok = cache_module.put(test_key, nil)

        Process.sleep(50)

        assert {:ok, nil} = cache_module.get(test_key)
      end
    end
  end
end
