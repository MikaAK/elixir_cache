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

  @hash_fields ["field_1", "field_2"]
  @hash_vals ["value", "value"]
  @hash_field_vals Enum.zip(@hash_fields, @hash_vals)

  @atom_hash_fields [:a, :b]
  @atom_hash_vals [1, 2]
  @atom_hash_field_vals Enum.zip(@atom_hash_fields, @atom_hash_vals)

  setup %{test: test} do
    start_supervised!({Cache, [RedisCache]})

    keys = Cache.Redis.command!(@cache_name, ["KEYS", "#{@cache_name}:#{test_key(test, "*")}"])

    if length(keys) > 0 do
      Cache.Redis.command!(@cache_name, ["DEL"] ++ keys)
    end

    :ok
  end

  describe "&scan/1" do
    setup %{test: test} do
      Enum.each(1..100, fn idx ->
        RedisCache.put(test_key(test, "key_#{idx}"), idx)
      end)
    end

    test "accepts a match opt", %{test: test} do
      scan_opts = [match: "#{test}:key_1*"]
      assert {:ok, elements} = RedisCache.scan(scan_opts)
      assert length(elements) === 12
    end

    test "accepts a count opt", %{test: test} do
      scan_opts = [match: "#{test}:*", count: 100]
      assert {:ok, elements} = RedisCache.scan(scan_opts)
      assert length(elements) === 100
    end

    test "accepts a type arg", %{test: test} do
      scan_opts = [match: "#{test}:key_1*", type: "zset"]
      assert {:ok, elements} = RedisCache.scan(scan_opts)
      assert Enum.empty?(elements)
    end

    test "returns all keys in the cache" do
      assert {:ok, elements} = RedisCache.scan()
      assert length(elements) >= 100
    end
  end

  describe "&hash_scan/2" do
    setup %{test: test} do
      test_key = test_key(test, "key_hash")
      field_values = Enum.map(1..100, &{"field_#{&1}", &1})
      RedisCache.hash_set_many([{test_key, field_values}])

      {:ok, test_key: test_key}
    end

    test "returns all fields in a hash", %{test_key: test_key} do
      assert {:ok, elements} = RedisCache.hash_scan(test_key)
      assert length(elements) === 100
    end

    test "accepts a match opt", %{test_key: test_key} do
      scan_opts = [match: "field_*"]
      assert {:ok, elements} = RedisCache.hash_scan(test_key, scan_opts)
      assert length(elements) === 100

      scan_opts = [match: "field_1*"]
      assert {:ok, elements} = RedisCache.hash_scan(test_key, scan_opts)
      assert length(elements) === 12
    end

    test "accepts a count opt", %{test_key: test_key} do
      scan_opts = [count: 100]
      assert {:ok, elements} = RedisCache.hash_scan(test_key, scan_opts)
      assert length(elements) === 100
    end

    test "decodes returned values", %{test_key: test_key} do
      scan_opts = [match: "field_1"]
      assert {:ok, [{"field_1", 1}]} = RedisCache.hash_scan(test_key, scan_opts)
    end
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
    setup :put_hash

    test "retrieves and decodes a value from a hash", %{hash: key} do
      assert {:ok, "value"} = RedisCache.hash_get(key, "field_1")
    end

    test "returns nil for missing values", %{hash: key_1} do
      assert {:ok, nil} = RedisCache.hash_get(key_1, "field_3")
    end
  end

  describe "&hash_delete/2" do
    setup :put_hash

    test "deletes a field from a hash", %{hash: key} do
      assert {:ok, 1} = RedisCache.hash_delete(key, "field_1")
    end
  end

  describe "&hash_values/1" do
    setup :put_hash

    test "retrieves and decodes values from a hash", %{hash: key} do
      assert {:ok, ["value", "value"]} = RedisCache.hash_values(key)
    end
  end

  describe "&hash_set_many/1" do
    test "sets many keys", %{test: test} do
      test_key_1 = test_key(test, "1")
      test_key_2 = test_key(test, "2")

      set_1 = {test_key_1, @hash_field_vals}
      set_2 = {test_key_2, @atom_hash_field_vals}

      {:ok, [2]} = RedisCache.hash_set_many([set_1])
      {:ok, [0, 2]} = RedisCache.hash_set_many([set_1, set_2])
    end
  end

  describe "&hash_get_all/1" do
    setup :put_hash

    test "gets complete hash by key", %{hash: key} do
      {:ok, %{"field_1" => "value", "field_2" => "value"}} = RedisCache.hash_get_all(key)
    end
  end

  describe "&hash_get_many/1" do
    setup [:put_hash, :put_hash_with_atom_fields]

    test "gets many fields from a key", %{hash: key_1} do
      {:ok, [@hash_vals]} = RedisCache.hash_get_many([{key_1, @hash_fields}])
    end

    test "gets many fields from many keys", %{hash: key_1, atom_hash: key_2} do
      {:ok, [@atom_hash_vals, @hash_vals]} =
        RedisCache.hash_get_many([{key_2, @atom_hash_fields}, {key_1, @hash_fields}])
    end

    test "handles missing values", %{hash: key_1, atom_hash: key_2} do
      {:ok, [[1, nil, 2], @hash_vals]} =
        RedisCache.hash_get_many([{key_2, [:a, :c, :b]}, {key_1, @hash_fields}])
    end
  end

  defp test_key(test, key), do: "#{test}:#{key}"

  defp put_hash(%{test: test}) do
    test_key = test_key(test, "hash")
    {:ok, [2]} = RedisCache.hash_set_many([{test_key, @hash_field_vals}])

    {:ok, hash: test_key}
  end

  defp put_hash_with_atom_fields(%{test: test}) do
    test_key = test_key(test, "atom_hash")
    {:ok, [2]} = RedisCache.hash_set_many([{test_key, @atom_hash_field_vals}])

    {:ok, atom_hash: test_key}
  end
end
