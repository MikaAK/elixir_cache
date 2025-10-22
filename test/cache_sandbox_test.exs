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
  @json_test_value %{
    some_integer: 1234,
    some_array: [1, 2, 3, 4],
    some_empty_array: [],
    some_map: %{one: 1, two: 2, three: 3, four: 4}
  }

  setup do
    Cache.SandboxRegistry.start(TestCache)
    json_test_key = Base.encode32(:crypto.strong_rand_bytes(64))
    :ok = TestCache.json_set(json_test_key, @json_test_value)

    %{key: json_test_key}
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

  describe "&json_get/1" do
    test "gets full json item", %{key: key} do
      assert {:ok,
              %{
                "some_integer" => 1234,
                "some_array" => [1, 2, 3, 4],
                "some_empty_array" => [],
                "some_map" => %{"one" => 1, "two" => 2, "three" => 3, "four" => 4}
              }} === TestCache.json_get(key)
    end

    test "returns tuple with :ok and nil if key is not found" do
      assert {:ok, nil} === TestCache.json_get("non_existing")
    end
  end

  describe "&json_get/2" do
    test "gets an item at path", %{key: key} do
      assert {:ok, @json_test_value.some_map.one} === TestCache.json_get(key, [:some_map, :one])

      assert {:ok, Enum.at(@json_test_value.some_array, 0)} ===
               TestCache.json_get(key, [:some_array, 0])
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

  describe "&json_set/2" do
    test "sets a full json item", %{key: key} do
      assert :ok = TestCache.json_set(key, %{test: 1})
      assert {:ok, %{"test" => 1}} = TestCache.json_get(key)
    end
  end

  describe "&json_set/3" do
    test "updates a json path", %{key: key} do
      assert :ok = TestCache.json_set(key, [:some_map, :one], 4)
      assert {:ok, 4} = TestCache.json_get(key, [:some_map, :one])
      assert :ok = TestCache.json_set(key, ["some_map.one"], 5)
      assert {:ok, 5} = TestCache.json_get(key, [:some_map, :one])
    end

    test "returns error tuple if key does not exist" do
      assert {:error,
              %ErrorMessage{
                message: "ERR new objects must be created at the root",
                code: :bad_request,
                details: nil
              }} === TestCache.json_set("non_existing", [:some_map, :one], 4)
    end

    test "returns :ok and nil if key exists but not the path", %{key: key} do
      assert {:ok, nil} = TestCache.json_set(key, [:some_other_map, :two], 4)

      assert {:ok,
              %{
                "some_integer" => 1234,
                "some_array" => [1, 2, 3, 4],
                "some_empty_array" => [],
                "some_map" => %{"one" => 1, "two" => 2, "three" => 3, "four" => 4}
              }} === TestCache.json_get(key)
    end

    test "ignores'.' as path", %{key: key} do
      assert :ok = TestCache.json_set(key, ["."], "some value")
      assert {:ok, "some value"} === TestCache.json_get(key)
      assert {:ok, "some value"} === TestCache.json_get(key, ["."])
    end
  end

  describe "&hash_set_many/2" do
    test "returns ok tuple when ttl is passed", %{key: key} do
      assert {:ok, [1, 1]} = TestCache.hash_set_many([{key, [{"some_key", "some_value"}]}], 1_000)
    end

    test "returns ok atom when ttl is not passed", %{key: key} do
      assert :ok = TestCache.hash_set_many([{key, [{"some_key", "some_value"}]}])
    end

    test "accepts map and list values", %{key: key} do
      assert {:ok, [1, 1]} = TestCache.hash_set_many([{key, [{"some_key", "some_value"}]}], 1_000)

      assert {:ok, [1, 1]} =
               TestCache.hash_set_many([{key, %{"some_key" => "some_value"}}], 1_000)

      assert {:ok, [1, 1]} =
               TestCache.hash_set_many(%{key => [{"some_key", "some_value"}]}, 1_000)

      assert {:ok, [1, 1]} =
               TestCache.hash_set_many(%{key => %{"some_key" => "some_value"}}, 1_000)
    end
  end
end
