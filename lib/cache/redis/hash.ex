defmodule Cache.Redis.Hash do
  @moduledoc """
  Contains functions for interfacing with redis hash functions
  """

  alias Cache.{Redis, TermEncoder}

  def hash_scan(pool_name, key, scan_opts, opts) do
    with {:ok, field_values} <-
           Redis.Global.scan_collection(pool_name, "HSCAN", key, scan_opts, opts) do
      field_values =
        field_values
        |> Stream.chunk_every(2)
        |> Enum.map(fn [field, value] ->
          {maybe_decode_hash_field(field), TermEncoder.decode(value)}
        end)

      {:ok, field_values}
    end
  end

  def hash_get(pool_name, key, field, opts) do
    field = maybe_encode_hash_field(field, opts[:compression_level])

    with {:ok, value} when not is_nil(value) <-
           Redis.Global.command(pool_name, ["HGET", Redis.Global.cache_key(pool_name, key), field], opts) do
      {:ok, TermEncoder.decode(value)}
    end
  end

  def hash_get_all(pool_name, key, opts) do
    with {:ok, data} <- Redis.Global.command(pool_name, ["HGETALL", Redis.Global.cache_key(pool_name, key)], opts) do
      hash =
        data
        |> Enum.chunk_every(2)
        |> Map.new(fn [field, value] ->
          {maybe_decode_hash_field(field), TermEncoder.decode(value)}
        end)

      {:ok, hash}
    end
  end

  def hash_get_many(pool_name, key_fields, opts) do
    commands =
      Enum.map(key_fields, fn {key, fields} ->
        fields = Enum.map(fields, &maybe_encode_hash_field(&1, opts[:compression_level]))

        ["HMGET", Redis.Global.cache_key(pool_name, key)] ++ fields
      end)

    with {:ok, data} <- Redis.Global.pipeline(pool_name, commands, opts) do
      values = Enum.map(data, fn values -> Enum.map(values, &TermEncoder.decode/1) end)

      {:ok, values}
    end
  end

  def hash_set(pool_name, key, field, value, nil, opts) do
    Redis.Global.command(
      pool_name,
      redis_hset_command(pool_name, key, field, value, opts),
      opts
    )
  end

  def hash_set(pool_name, key, field, value, ttl, opts) do
    command = redis_hset_command(pool_name, key, field, value, opts)
    expire = redis_pexpire_command(pool_name, key, ttl)

    Redis.Global.pipeline(pool_name, [command, expire], opts)
  end

  defp redis_hset_command(pool_name, key, field, value, opts) do
    field = maybe_encode_hash_field(field, opts)
    value = TermEncoder.encode(value, opts[:compression_level])
    ["HSET", Redis.Global.cache_key(pool_name, key), field, value]
  end

  defp redis_pexpire_command(pool_name, key, ttl) do
    ["PEXPIRE", Redis.Global.cache_key(pool_name, key), ttl]
  end

  def hash_set_many(pool_name, key_values, ttl, opts) do
    commands =
      Enum.map(key_values, fn {key, field_values} ->
        field_values =
          field_values
          |> Enum.map(fn {field, value} ->
            [
              maybe_encode_hash_field(field, opts[:compression_level]),
              TermEncoder.encode(value, opts[:compression_level])
            ]
          end)
          |> List.flatten()

        ["HSET", Redis.Global.cache_key(pool_name, key) | field_values]
      end)

    expiries =
      if ttl do
        Enum.map(key_values, fn {key, _} ->
          redis_pexpire_command(pool_name, key, ttl)
        end)
      else
        []
      end

    Redis.Global.pipeline(pool_name, commands ++ expiries, opts)
  end

  def hash_delete(pool_name, key, field, opts) do
    field = maybe_encode_hash_field(field, opts[:compression_level])
    Redis.Global.command(pool_name, ["HDEL", Redis.Global.cache_key(pool_name, key), field], opts)
  end

  def hash_values(pool_name, key, opts) do
    with {:ok, data} <- Redis.Global.command(pool_name, ["HVALS", Redis.Global.cache_key(pool_name, key)], opts) do
      values =
        Enum.map(data, fn value ->
          TermEncoder.decode(value)
        end)

      {:ok, values}
    end
  end

  defp maybe_decode_hash_field(field) when is_binary(field), do: field

  defp maybe_decode_hash_field(field) do
    TermEncoder.decode(field)
  end

  defp maybe_encode_hash_field(field, _opts) when is_binary(field), do: field

  defp maybe_encode_hash_field(field, opts) do
    TermEncoder.encode(field, opts[:compression_level])
  end
end
