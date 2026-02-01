defmodule Cache.Redis.JSON do
  @moduledoc """
  Redis JSON operations for the Redis cache adapter.

  This module provides RedisJSON operations including JSON.GET, JSON.SET,
  JSON.DEL, JSON.NUMINCRBY, JSON.CLEAR, and JSON.ARRAPPEND. It handles
  JSON path serialization and automatic encoding/decoding.

  ## Features

  * JSON document get/set/delete operations
  * Path-based access to nested JSON data
  * Numeric increment operations
  * Array append operations
  * Automatic JSON encoding/decoding via `Cache.TermEncoder`

  ## Path Format

  Paths can be specified as a list of keys/indices:

      ["user", "address", "city"]     # => "user.address.city"
      ["items", 0, "name"]            # => "items[0].name"
  """

  alias Cache.{Redis, TermEncoder}

  def get(pool_name, key, nil, opts) do
    with {:ok, data} <- json_command(pool_name, key, "GET", [], opts) do
      {:ok, TermEncoder.decode_json(data)}
    end
  end

  def get(pool_name, key, path, opts) do
    with {:ok, data} <- json_command(pool_name, key, "GET", [serialize_path(path)], opts) do
      {:ok, TermEncoder.decode_json(data)}
    end
  end

  def set(pool_name, key, path, value, opts) do
    json_command(
      pool_name,
      key,
      "SET",
      [serialize_path(path), TermEncoder.encode_json(value)],
      opts
    )
  end

  def delete(pool_name, key, path, opts) do
    json_command(pool_name, key, "DEL", [serialize_path(path)], opts)
  end

  def incr(pool_name, key, path, value, opts) do
    with {:ok, value} <-
           json_command(
             pool_name,
             key,
             "NUMINCRBY",
             [serialize_path(path), to_string(value)],
             opts
           ) do
      {:ok, String.to_integer(value)}
    end
  end

  def clear(pool_name, key, path, opts) do
    json_command(
      pool_name,
      key,
      "CLEAR",
      [serialize_path(path)],
      opts
    )
  end

  def array_append(pool_name, key, path, values, opts) when is_list(values) do
    json_command(
      pool_name,
      key,
      "ARRAPPEND",
      [serialize_path(path) | Enum.map(values, &TermEncoder.encode_json/1)],
      opts
    )
  end

  def array_append(pool_name, key, path, value, opts) do
    json_command(
      pool_name,
      key,
      "ARRAPPEND",
      [serialize_path(path), TermEncoder.encode_json(value)],
      opts
    )
  end

  def serialize_path(nil) do
    "$"
  end

  def serialize_path(path_list) do
    Enum.reduce(path_list, "", &append_to_path(&2, &1))
  end

  def append_to_path("", field) do
    to_string(field)
  end

  def append_to_path(path, field) when is_atom(field) do
    append_to_path(path, to_string(field))
  end

  def append_to_path(path, index) when is_integer(index) do
    "#{path}[#{index}]"
  end

  def append_to_path(path, field) when is_binary(field) do
    "#{path}.#{field}"
  end

  defp json_command(pool_name, key, command, commands, opts) do
    Redis.Global.command(
      pool_name,
      [
        "JSON.#{command}",
        Redis.Global.cache_key(pool_name, key) | commands
      ],
      opts
    )
  end
end
