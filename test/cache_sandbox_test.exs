defmodule CacheSandboxTest do
  use ExUnit.Case, async: true

  defmodule TestCache do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_sandbox,
      opts: [uri: "redis://localhost:6379"],
      sandbox?: Mix.env() === :test
  end

  @cache_key "SomeKey"
  @cache_value 1234
  @cache_path [:a, :b]

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

  describe "&json_get/2" do
    test "gets an item at path" do
      assert :ok = TestCache.json_set(@cache_key, @cache_path, @cache_value)
      assert {:ok, @cache_value} = TestCache.json_get(@cache_key, @cache_path)
      assert {:ok, @cache_value} = TestCache.json_get(@cache_key, ["a.b"])
    end

    test "returns :error tuple if path not found" do
      assert {:error,
              %ErrorMessage{
                message: "ERR Path '$.c.d' does not exist",
                code: :not_found,
                details: nil
              }} === TestCache.json_get(@cache_key, ["c.d"])

    end
  end
end
