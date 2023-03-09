defmodule Cache.RedisTest do
  @moduledoc """
  Redis-adapter-specific tests.

  """
  use ExUnit.Case, async: true

  @cache_name :test_cache_redis_adapter

  defmodule RedisCache do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis_adapter,
      opts: [uri: "redis://localhost:6379"]
  end

  setup %{test: test} do
    start_supervised!({Cache, [RedisCache]})

    keys = Cache.Redis.command!(@cache_name, ["KEYS", "#{@cache_name}:#{test_key(test, "*")}"])

    if length(keys) > 0 do
      Cache.Redis.command!(@cache_name, ["DEL"] ++ keys)
    end

    :ok
  end

  describe "&hash_set/3" do
    test "encodes fields and values in a hash as binaries", %{test: test} do
      test_key = test_key(test, "key")
      {:ok, 1} = RedisCache.hash_set(test_key, "field", "value")

      assert {:ok, [<<field::binary>>, <<value::binary>>]} =
               Cache.Redis.command(@cache_name, ["HGETALL", "#{@cache_name}:#{test_key}"])

      refute String.valid?(field)
      refute String.valid?(value)
    end
  end

  describe "&hash_get/2" do
    setup :put_hash_key

    test "retrieve's and decodes a value from a hash", %{key: key} do
      assert {:ok, "value"} = RedisCache.hash_get(key, "field_1")
    end
  end

  describe "&hash_delete/2" do
    setup :put_hash_key

    test "deletes a field from a hash", %{key: key} do
      assert {:ok, 1} = RedisCache.hash_delete(key, "field_1")
    end
  end

  describe "&hash_values/1" do
    setup :put_hash_key

    test "retrieves and decodes values from a hash", %{key: key} do
      assert {:ok, ["value", "value"]} = RedisCache.hash_values(key)
    end
  end

  describe "&hash_set_many/1" do
    test "sets many keys", %{test: test} do
      test_key_1 = test_key(test, "1")
      test_key_2 = test_key(test, "2")

      set_1 = {test_key_1, [{"field_1", "value"}, {"field_2", "value"}]}
      set_2 = {test_key_2, [{"field_1", "value"}, {"field_2", "value"}]}

      {:ok, [2]} = RedisCache.hash_set_many([set_1])
      {:ok, [0, 2]} = RedisCache.hash_set_many([set_1, set_2])
    end
  end

  describe "&hash_get_all/1" do
    setup :put_hash_key

    test "gets complete hash by key", %{key: key} do
      {:ok, %{"field_1" => "value", "field_2" => "value"}} = RedisCache.hash_get_all(key)
    end
  end

  defp test_key(test, key), do: "#{test}:#{key}"

  defp put_hash_key(%{test: test}) do
    test_key = test_key(test, "key")

    {:ok, [2]} =
      RedisCache.hash_set_many([
        {test_key, [{"field_1", "value"}, {"field_2", "value"}]}
      ])

    {:ok, key: test_key}
  end

  describe "&json_set/3" do
    test "sets values into json maps with a path" do
      key = "KEY_#{Enum.random(100_000_000..999_999_999)}"

      assert :ok = RedisCache.json_set(key, %{
        "test" => 123,
        "value" => %{"test" => 321}
      })

      assert :ok = RedisCache.json_set(key, ["test"], 111)

      assert {:ok, %{
        "test" => 111,
        "value" => %{"test" => 321}
      }} === RedisCache.json_get(key)
    end
  end

  describe "&json_get/2" do
    setup :setup_json_item

    test "gets entire json from redis", %{key: key} do
      assert {:ok, %{
        "test_value" => %{"map_key" => 1, "other_key" => 2},
        "some_value" => 321
      }} = RedisCache.json_get(key)
    end

    test "gets items from redis json at a specific path", %{key: key} do
      assert {:ok, 321} = RedisCache.json_get(key, "some_value")
    end
  end

  describe "&json_incr/2" do
    setup :setup_json_item

    test "increments a value at a path", %{key: key} do
      assert {:ok, 322} = RedisCache.json_incr(key, "some_value")

      assert {:ok, 322} = RedisCache.json_get(key, "some_value")
    end
  end

  describe "&json_delete/2" do
    setup :setup_json_item

    test "deletes an item at a path", %{key: key} do
      assert {:ok, 1} = RedisCache.json_delete(key, "test_value")

      assert {:ok, %{
      "some_value" => 321
      }} = RedisCache.json_get(key)
    end
  end

  describe "&json_clear/2" do
    setup :setup_json_item

    test "clears json paths to nil", %{key: key} do
      assert {:ok, 1} = RedisCache.json_clear(key, "some_value")

      assert {:ok, 0} = RedisCache.json_get(key, "some_value")
    end
  end

  describe "&json_array_append/3" do
    test "json works with paths" do
      key = "KEY_#{Enum.random(100_000_000..999_999_999)}"
      assert :ok = RedisCache.json_set(key, %{"value" => []})


      assert {:ok, 3} = RedisCache.json_array_append(key, "value", [1, 2, 3])

      assert {:ok, %{"value" => [1, 2, 3]}} = RedisCache.json_get(key)
    end
  end

  defp setup_json_item(ctx) do
    key = "KEY_#{Enum.random(100_000_000..999_999_999)}"

    :ok = RedisCache.json_set(key, %{
      "test_value" => %{"map_key" => 1, "other_key" => 2},
      "some_value" => 321
    })

    {:ok, Map.put(ctx, :key, key)}
  end
end
