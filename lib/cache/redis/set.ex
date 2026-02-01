defmodule Cache.Redis.Set do
  @moduledoc """
  Redis Set operations for the Redis cache adapter.

  This module provides set-specific Redis operations including SMEMBERS and SADD.
  Set values are automatically encoded/decoded using `Cache.TermEncoder`.

  ## Features

  * Add members to sets with automatic encoding
  * Retrieve all set members with automatic decoding
  """

  alias Cache.{Redis, TermEncoder}

  def smembers(pool_name, key, opts) do
    with {:ok, values} <-
           Redis.Global.command(
             pool_name,
             [
               "SMEMBERS",
               Redis.Global.cache_key(pool_name, key)
             ],
             opts
           ) do
      {:ok, TermEncoder.decode(values)}
    end
  end

  def sadd(pool_name, key, value, opts) do
    Redis.Global.command(
      pool_name,
      [
        "SADD",
        Redis.Global.cache_key(pool_name, key),
        TermEncoder.encode(value, opts[:compression_level])
      ],
      opts
    )
  end
end
