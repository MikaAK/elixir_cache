defmodule Cache.Redis.Set do
  @moduledoc false

  alias Cache.{Redis, TermEncoder}

  def smembers(pool_name, key, opts) do
    with {:ok, values} <- Redis.Global.command(pool_name, [
      "SMEMBERS",
      Redis.Global.cache_key(pool_name, key)
    ], opts) do
      {:ok, TermEncoder.decode(values)}
    end
  end

  def sadd(pool_name, key, value, opts) do
    Redis.Global.command(pool_name, [
      "SADD",
      Redis.Global.cache_key(pool_name, key),
      TermEncoder.encode(value, opts[:compression_level])
    ], opts)
  end
end
