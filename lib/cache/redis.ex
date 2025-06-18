defmodule Cache.Redis do
  @opts_definition [
    uri: [
      type: :string,
      doc: "The connection uri to redis",
      required: true
    ],

    size: [
      type: :pos_integer,
      doc: "The amount of workers in the pool"
    ],

    max_overflow: [
      type: :pos_integer,
      doc: "The amount of max overflow the pool can handle"
    ],

    strategy: [
      type: {:in, [:fifo, :lifo]},
      doc: "The type of queue to use for poolboy"
    ]
  ]

  @moduledoc """
  Redis adapter for distributed caching with ElixirCache.

  This adapter provides a connection pool to Redis, enabling distributed caching
  across multiple nodes or services. It supports the standard Cache behavior plus
  additional Redis-specific operations like hash manipulation, JSON operations, and sets.

  ## Features

  * Connection pooling for efficient Redis access
  * Support for Redis URI connection strings
  * Hash operations for storing field-value pairs within a key
  * JSON operations for working with complex nested data structures
  * Set operations for managing collections
  * Direct access to Redis commands via pipeline and command functions

  ## Options
  #{NimbleOptions.docs(@opts_definition)}

  ## Example

  ```elixir
  defmodule MyApp.RedisCache do
    use Cache,
      adapter: Cache.Redis,
      name: :my_app_redis_cache,
      opts: [
        uri: "redis://localhost:6379",
        size: 10,
        max_overflow: 5
      ]
  end
  ```
  """

  alias Cache.Redis

  @behaviour Cache

  @default_opts [size: 50, max_overflow: 20]

  defmacro __using__(_opts) do
    quote do
      def scan(scan_opts \\ []) do
        @cache_adapter.scan(@cache_name, scan_opts, adapter_options())
      end

      def hash_scan(key, scan_opts \\ []) do
        @cache_adapter.hash_scan(@cache_name, maybe_sandbox_key(key), scan_opts, adapter_options())
      end

      def hash_get(key, field) do
        @cache_adapter.hash_get(@cache_name, maybe_sandbox_key(key), field, adapter_options())
      end

      def hash_get_all(key) do
        @cache_adapter.hash_get_all(@cache_name, maybe_sandbox_key(key), adapter_options())
      end

      def hash_get_many(key_fields) do
        @cache_adapter.hash_get_many(@cache_name, key_fields, adapter_options())
      end

      def hash_set(key, field, value, ttl \\ nil) do
        @cache_adapter.hash_set(@cache_name, maybe_sandbox_key(key), field, value, ttl, adapter_options())
      end

      def hash_set_many(keys_fields_values, ttl \\ nil) do
        @cache_adapter.hash_set_many(@cache_name, keys_fields_values, ttl, adapter_options())
      end

      def hash_delete(key, field) do
        @cache_adapter.hash_delete(@cache_name, maybe_sandbox_key(key), field, adapter_options())
      end

      def hash_values(key) do
        @cache_adapter.hash_values(@cache_name, maybe_sandbox_key(key), adapter_options())
      end

      def json_get(key, path \\ nil) do
        @cache_adapter.json_get(@cache_name, maybe_sandbox_key(key), path, adapter_options())
      end

      def json_set(key, path \\ nil, value) do
        @cache_adapter.json_set(@cache_name, maybe_sandbox_key(key), path, value, adapter_options())
      end

      def json_delete(key, path) do
        @cache_adapter.json_delete(@cache_name, maybe_sandbox_key(key), path, adapter_options())
      end

      def json_incr(key, path, value \\ 1) do
        @cache_adapter.json_incr(@cache_name, maybe_sandbox_key(key), path, value, adapter_options())
      end

      def json_clear(key, path) do
        @cache_adapter.json_clear(@cache_name, maybe_sandbox_key(key), path, adapter_options())
      end

      def json_array_append(key, path, value_or_values) do
        @cache_adapter.json_array_append(@cache_name, maybe_sandbox_key(key), path, value_or_values, adapter_options())
      end

      def smembers(key, opts) do
        @cache_adapter.smembers(
          @cache_name,
          maybe_sandbox_key(key),
          Keyword.merge(adapter_options(), opts)
        )
      end

      def sadd(key, value, opts \\ []) do
        @cache_adapter.sadd(
          @cache_name,
          maybe_sandbox_key(key),
          value,
          Keyword.merge(adapter_options(), opts)
        )
      end

      def command(command, opts \\ []) do
        @cache_adapter.command(@cache_name, command, opts)
      end

      def command!(command, opts \\ []) do
        @cache_adapter.command!(@cache_name, command, opts)
      end

      def pipeline(commands, opts \\ []) do
        @cache_adapter.pipeline(@cache_name, commands, opts)
      end

      def pipeline!(commands, opts \\ []) do
        @cache_adapter.pipeline!(@cache_name, commands, opts)
      end
    end
  end

  @impl Cache
  def opts_definition, do: @opts_definition

  @impl Cache
  def start_link(opts) do
    if !opts[:uri] do
      raise "Must supply a redis uri"
    end

    Redix.start_link(opts[:uri], Keyword.delete(opts, :uri))
  end

  @impl Cache
  def child_spec({pool_name, opts}) do
    {pool_opts, redis_opts} = Keyword.split(opts, [:size, :max_overflow])

    :poolboy.child_spec(pool_name, pool_config(pool_name, pool_opts), redis_opts)
  end

  def pool_config(pool_name, opts) do
    opts = Keyword.merge(@default_opts, opts)

    [
      name: {:local, pool_name},
      worker_module: Cache.Redis,
      size: opts[:size],
      max_overflow: opts[:max_overflow],
      strategy: opts[:strategy] || :fifo
    ]
  end

  @impl Cache
  def put(pool_name, key, ttl, value, opts \\ []) do
    with {:ok, "OK"} <- Redis.Global.command(pool_name, redis_set_command(pool_name, key, ttl, value), opts) do
      :ok
    end
  end

  defp redis_set_command(pool_name, key, _ttl, nil) do
    ["DEL", Redis.Global.cache_key(pool_name, key)]
  end

  defp redis_set_command(pool_name, key, nil, value) do
    ["SET", Redis.Global.cache_key(pool_name, key), value]
  end

  defp redis_set_command(pool_name, key, ttl, value) do
    key = Redis.Global.cache_key(pool_name, key)

    ["SETEX", key, ms_to_nearest_sec(ttl), value]
  end

  def ms_to_nearest_sec(ms) do
    round(ms / :timer.seconds(1))
  end

  @impl Cache
  def get(pool_name, key, opts \\ []) do
    Redis.Global.command(pool_name, ["GET", Redis.Global.cache_key(pool_name, key)], opts)
  end

  @impl Cache
  def delete(pool_name, key, opts \\ []) do
    with {:ok, _} <- Redis.Global.command(pool_name, ["DEL", Redis.Global.cache_key(pool_name, key)], opts) do
      :ok
    end
  end

  defdelegate pipeline(pool_name, command, opts \\ []), to: Redis.Global

  defdelegate pipeline!(pool_name, command, opts \\ []), to: Redis.Global

  defdelegate command(pool_name, command, opts \\ []), to: Redis.Global

  defdelegate command!(pool_name, command, opts \\ []), to: Redis.Global

  defdelegate scan(pool_name, scan_opts, opts \\ []), to: Redis.Global


  defdelegate hash_scan(pool_name, key, scan_opts, opts \\ []), to: Redis.Hash

  defdelegate hash_get(pool_name, key, field, opts \\ []), to: Redis.Hash

  defdelegate hash_get_all(pool_name, key, opts \\ []), to: Redis.Hash

  defdelegate hash_get_many(pool_name, key_fields, opts \\ []), to: Redis.Hash

  defdelegate hash_set(pool_name, key, field, value, ttl, opts \\ []), to: Redis.Hash

  defdelegate hash_set_many(pool_name, keys_fields_values, ttl, opts \\ []), to: Redis.Hash

  defdelegate hash_delete(pool_name, key, field, opts \\ []), to: Redis.Hash

  defdelegate hash_values(pool_name, key, opts \\ []), to: Redis.Hash

  defdelegate json_get(pool_name, key, path, opts \\ []), to: Redis.JSON, as: :get

  defdelegate json_set(pool_name, key, path, value, opts \\ []), to: Redis.JSON, as: :set

  defdelegate json_delete(pool_name, key, path, opts \\ []), to: Redis.JSON, as: :delete

  defdelegate json_incr(pool_name, key, path, value \\ 1, opts \\ []), to: Redis.JSON, as: :incr

  defdelegate json_clear(pool_name, key, path, opts \\ []), to: Redis.JSON, as: :clear

  defdelegate json_array_append(pool_name, key, path, value_or_values, opts \\ []),
    to: Redis.JSON,
    as: :array_append

  defdelegate smembers(pool_name, key, opts),
    to: Redis.Set

  defdelegate sadd(pool_name, key, value, opts),
    to: Redis.Set
end
