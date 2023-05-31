defmodule Cache.RedisJSONTest do
  @moduledoc """
  Redis-adapter-specific tests.

  """
  use ExUnit.Case, async: true

  @test_value %{
    some_integer: 1234,
    some_array: [1, 2, 3, 4],
    some_empty_array: [],
    some_map: %{one: 1, two: 2, three: 3, four: 4}
  }

  defmodule RedisCache do
    use Cache,
      adapter: Cache.Redis,
      name: :test_json_redis_adapter,
      opts: [uri: "redis://localhost:6379"]
  end

  setup do
    start_supervised!({Cache, [RedisCache]})
    test_key = Base.encode32(:crypto.strong_rand_bytes(64))

    :ok = RedisCache.json_set(test_key, @test_value)

    %{key: test_key}
  end

  describe "&json_get/1" do
    test "gets full json item", %{key: key} do
      assert {:ok, %{
        "some_integer" => 1234,
        "some_array" => [1, 2, 3, 4],
        "some_empty_array" => [],
        "some_map" => %{"one" => 1, "two" => 2, "three" => 3, "four" => 4}
      }} === RedisCache.json_get(key)
    end

    test "returns :ok and nil if key not found" do
      assert {:ok, nil} === RedisCache.json_get("non_existing")
    end
  end

  describe "&json_get/2" do
    test "gets an item at path", %{key: key} do
      assert {:ok, @test_value.some_map.one} === RedisCache.json_get(key, [:some_map, :one])
      assert {:ok, Enum.at(@test_value.some_array, 0)} === RedisCache.json_get(key, [:some_array, 0])
    end

    test "returns :error tuple if path not found", %{key: key} do
      assert {:error,
              %ErrorMessage{
                message: "ERR Path '$.non_existing.path' does not exist",
                code: :not_found,
                details: nil
              }} === RedisCache.json_get(key, [:non_existing, :path])
    end
  end

  describe "&json_set/2" do
    test "sets a full json item", %{key: key} do
      assert :ok = RedisCache.json_set(key, %{test: 1})
      assert {:ok, %{"test" => 1}} = RedisCache.json_get(key)
    end
  end

  describe "&json_set/3" do
    test "updates a json path", %{key: key} do
      assert :ok = RedisCache.json_set(key, [:some_map, :one], 4)
      assert {:ok, 4} = RedisCache.json_get(key, [:some_map, :one])
    end

    test "returns error tuple if key does not exist" do
      assert {:error,
              %ErrorMessage{
                message: "ERR new objects must be created at the root",
                code: :bad_request,
                details: nil
              }} === RedisCache.json_set("non_existing", [:some_map, :one], 4)
    end

    test "returns :ok and nil if key exists but not the path", %{key: key} do
      assert {:ok, nil} = RedisCache.json_set(key, [:some_other_map, :two], 4)

      assert {:ok,
              %{
                "some_integer" => 1234,
                "some_array" => [1, 2, 3, 4],
                "some_empty_array" => [],
                "some_map" => %{"one" => 1, "two" => 2, "three" => 3, "four" => 4}
              }} === RedisCache.json_get(key)
    end

    test "ignores'.' as path", %{key: key} do
      assert :ok = RedisCache.json_set(key, ["."], "some value")
      assert {:ok, "some value"} === RedisCache.json_get(key)
      assert {:ok, "some value"} === RedisCache.json_get(key, ["."])
    end
  end

  describe "&json_delete/2" do
    test "deletes a json item at path", %{key: key} do
      assert {:ok, 1} = RedisCache.json_delete(key, [:some_map, :one])
      assert {:ok, %{"some_map" => some_map}} = RedisCache.json_get(key)
      refute some_map["one"]
    end
  end

  describe "&json_incr/3" do
    test "increments a json path by 1", %{key: key} do
      assert {:ok, 1235} = RedisCache.json_incr(key, [:some_integer])
      assert {:ok, 1235} = RedisCache.json_get(key, [:some_integer])
    end
  end

  describe "&json_clear/3" do
    test "sets a json path to 0 or clears the array", %{key: key} do
      assert {:ok, 1} = RedisCache.json_clear(key, [:some_map, :one])
      assert {:ok, 0} = RedisCache.json_get(key, [:some_map, :one])
    end
  end

  describe "&json_array_append/4" do
    test "adds an item to a json array at a path", %{key: key} do
      assert {:ok, 5} = RedisCache.json_array_append(key, ["some_array"], 321)
      assert {:ok, 1} = RedisCache.json_array_append(key, ["some_empty_array"], 321)

      assert {:ok, [1, 2, 3, 4, 321]} = RedisCache.json_get(key, ["some_array"])
      assert {:ok, [321]} = RedisCache.json_get(key, ["some_empty_array"])
    end
  end
end
