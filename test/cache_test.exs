defmodule CacheTest do
  use ExUnit.Case, async: true

  @adapter_configs [
    {Cache.Redis, [opts: [uri: "redis://localhost:6379"]]},
    {Cache.DETS, []},
    {Cache.ETS, []},
    {Cache.Agent, []},
    {Cache.PersistentTerm, []},
    {Cache.ConCache, [opts: [dirty?: false]]},
    {Cache.ConCache, [name_suffix: "DirtyConCache", opts: []]}
  ]

  @adapters Enum.map(@adapter_configs, fn {adapter, config} ->
    suffix = Keyword.get(config, :name_suffix, adapter |> Module.split() |> List.last())
    module_name = Module.concat(CacheTest.TestCache, suffix)
    cache_name = :"test_cache_#{suffix |> Macro.underscore()}"
    opts = Keyword.get(config, :opts, [])

    module_contents = quote do
      use Cache,
        adapter: unquote(adapter),
        name: unquote(cache_name),
        opts: unquote(opts)
    end

    Module.create(module_name, module_contents, Macro.Env.location(__ENV__))

    module_name
  end)

  for adapter <- @adapters do
    describe "#{adapter} &get/1 & &put/2 & &delete/1" do
      setup do
        start_supervised({Cache, [unquote(adapter)]})

        Process.sleep(100)

        :ok
      end

      test "puts into the cache and can get it back after" do
        test_key = Enum.random(1..100_000_000)
        value = %{some_value: Faker.App.name()}
        cache_module = unquote(adapter)

        assert {:ok, nil} = cache_module.get(test_key)
        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert {:ok, value} === cache_module.get(test_key)
      end

      test "deleting from cache works" do
        test_key = Enum.random(1..100_000_000)
        value = %{some_value: Faker.App.name()}
        cache_module = unquote(adapter)

        assert :ok = cache_module.put(test_key, value)

        Process.sleep(50)

        assert :ok = cache_module.delete(test_key)

        Process.sleep(50)

        assert {:ok, nil} = cache_module.get(test_key)
      end

      test "puts into the cache with nil acts like deleting" do
        test_key = Enum.random(1..100_000_000)
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

    describe "#{adapter} &get_or_create/1" do
      setup do
        start_supervised({Cache, [unquote(adapter)]})

        Process.sleep(100)

        :ok
      end

      test "finds an item in the cache that already exists" do
        test_key = Enum.random(1..100_000_000)
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
        test_key = Enum.random(1..100_000_000)
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
      assert_raise ArgumentError,
                   ~r/Bad option in adapter module TestCache.RedisRuntimeCallback!/,
                   fn ->
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
      assert_raise ArgumentError,
                   ~r/Bad option in adapter module TestCache.RedisRuntimeCallback!/,
                   fn ->
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
