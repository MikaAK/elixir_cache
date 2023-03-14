defmodule CacheTest do
  use ExUnit.Case, async: true

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

  defmodule TestCache.DirtyConCache do
    use Cache,
      adapter: Cache.ConCache,
      name: :test_cache_dets,
      opts: []
  end

  defmodule TestCache.ConCache do
    use Cache,
      adapter: Cache.ConCache,
      name: :test_cache_dets,
      opts: [dirty?: false]
  end

  defmodule TestCache.Agent do
    use Cache,
      adapter: Cache.Agent,
      name: :test_cache_agent,
      opts: []
  end

  @adapters [TestCache.Redis, TestCache.ETS, TestCache.Agent, TestCache.ConCache, TestCache.DirtyConCache]

  for adapter <- @adapters do
    describe "#{adapter} &get/1 & &put/2 & &delete/1" do
      setup do
        start_supervised({Cache, [unquote(adapter)]})

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
  end

  defmodule TestCache.RedisRuntimeMFA do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: {TestCache.RedisRuntimeMFA, :opts, []}

    def opts, do: [host: "localhost", port: 6379]
  end

  defmodule TestCache.RedisRuntimeCallback do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: &TestCache.RedisRuntimeCallback.opts/0

    def opts, do: [host: "localhost", port: 6379]
  end

  describe "&adapter_options/0: " do
    test "returns options from module function" do
      assert [host: "localhost", port: 6379] = TestCache.RedisRuntimeMFA.adapter_options()
    end

    test "returns options from callback function" do
      assert [host: "localhost", port: 6379] = TestCache.RedisRuntimeCallback.adapter_options()
    end

    test "returns application env config with name" do
      options = [host: "localhost", port: 6379]

      Application.put_env(:elixir_cache, TestCache.RedisRuntimeAppEnv, options)

      defmodule TestCache.RedisRuntimeAppEnv do
        use Cache,
          adapter: Cache.Redis,
          name: :test_cache_redis,
          opts: :elixir_cache
      end

      assert ^options = TestCache.RedisRuntimeAppEnv.adapter_options()
    end

    test "returns application env config with name and key" do
      options = [host: "localhost", port: 6379]

      Application.put_env(:elixir_cache, :cache, options)

      defmodule TestCache.RedisRuntimeAppEnvKey do
        use Cache,
          adapter: Cache.Redis,
          name: :test_cache_redis,
          opts: {:elixir_cache, :cache}
      end

      assert ^options = TestCache.RedisRuntimeAppEnvKey.adapter_options()
    end

    test "raises when opts options format is invalid" do
      assert_raise ArgumentError, ~r/Bad option in adapter module TestCache.RedisRuntimeCallback!/, fn ->
        Code.compile_string("""
        defmodule TestCache.RedisRuntimeCallback do
          use Cache,
            adapter: Cache.Redis,
            name: :test_cache_redis,
            opts: 1234
        end
        """)
      end
    end

    test "raises when no option passed" do
      assert_raise ArgumentError, ~r/Bad option in adapter module TestCache.RedisRuntimeCallback!/, fn ->
        Code.compile_string("""
        defmodule TestCache.RedisRuntimeCallback do
          use Cache,
            adapter: Cache.Redis,
            name: :test_cache_redis
        end
        """)
      end
    end
  end
end
