defmodule CacheSandboxTest do
  use ExUnit.Case, async: true

  defmodule TestCache do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: [uri: "redis://localhost:6379"],
      sandbox?: Mix.env() === :test
  end

  @cache_key "SomeKey"
  @cache_value 1234

  setup do
    Cache.SandboxRegistry.start(TestCache)

    :ok
  end

  describe "sandboxing caches" do
    test "inserts into cache" do
      assert :ok = TestCache.put(@cache_key, @cache_value)
      assert {:ok, @cache_value} = TestCache.get(@cache_key)
    end

    test "works to seperate caches between tests" do
      assert {:ok, nil} = TestCache.get(@cache_key)
    end
  end
end
