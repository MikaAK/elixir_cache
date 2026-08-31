defmodule Cache.RedisPoolOptsTest do
  @moduledoc """
  Pool options configured on a Redis cache must never reach `Redix`'s command
  functions.

  Redix validates command options with NimbleOptions and raises on anything it
  does not recognise, so a cache configured with `size:` — the documented way
  to size its poolboy pool — used to crash on every read and write.

  """
  use ExUnit.Case, async: true

  defmodule PooledRedisCache do
    use Cache,
      adapter: Cache.Redis,
      name: :test_pool_opts_redis_adapter,
      opts: [uri: "redis://localhost:6379", size: 2, max_overflow: 1]
  end

  setup do
    start_supervised!({Cache, [PooledRedisCache]})

    %{key: Base.encode32(:crypto.strong_rand_bytes(32))}
  end

  test "get/put/delete work when the cache config carries pool options", %{key: key} do
    assert {:ok, nil} = PooledRedisCache.get(key)
    assert :ok = PooledRedisCache.put(key, %{value: 1})
    assert {:ok, %{value: 1}} = PooledRedisCache.get(key)
    assert :ok = PooledRedisCache.delete(key)
    assert {:ok, nil} = PooledRedisCache.get(key)
  end

  test "the adapter still honours real command options", %{key: key} do
    assert :ok = PooledRedisCache.put(key, %{value: 2})

    assert {:ok, encoded} =
             Cache.Redis.get(:test_pool_opts_redis_adapter, key, timeout: 5_000)

    assert %{value: 2} = :erlang.binary_to_term(encoded)
  end
end
