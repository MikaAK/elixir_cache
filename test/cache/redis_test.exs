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

      assert {:ok, ["field", <<value::binary>>]} =
               Cache.Redis.command(@cache_name, ["HGETALL", "#{@cache_name}:#{test_key}"])

      refute String.valid?(value)
    end

    test "encodes non-binary hash fields as binaries", %{test: test} do
      test_key = test_key(test, "key")
      {:ok, 1} = RedisCache.hash_set(test_key, :field, "value")

      assert {:ok, [<<field::binary>>, <<value::binary>>]} =
               Cache.Redis.command(@cache_name, ["HGETALL", "#{@cache_name}:#{test_key}"])

      refute String.valid?(field)
      refute String.valid?(value)
    end
  end

  describe "&hash_get/2" do
    setup :put_hash_key

    test "retrieves and decodes a value from a hash", %{key: key} do
      assert {:ok, "value"} = RedisCache.hash_get(key, "field_1")
    end

    test "returns nil for missing values", %{key_1: key_1} do
      assert {:ok, nil} = RedisCache.hash_get(key_1, "field_3")
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
end
