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
    ]
  ]

  @moduledoc """
  This module interacts with redis using a pool of connections
  """

  alias Cache.TermEncoder

  @behaviour Cache

  @default_opts [size: 50, max_overflow: 20]

  defmacro __using__(_opts) do
    quote do
      def hash_get(key, field) do
        @cache_adapter.hash_get(@cache_name, key, field, @adapter_opts)
      end

      def hash_get_all(key) do
        @cache_adapter.hash_get_all(@cache_name, key, @adapter_opts)
      end

      def hash_set(key, field, value) do
        @cache_adapter.hash_set(@cache_name, key, field, value, @adapter_opts)
      end

      def hash_set_many(keys_fields_values, ttl \\ nil) do
        @cache_adapter.hash_set_many(@cache_name, keys_fields_values, ttl, @adapter_opts)
      end

      def hash_delete(key, field) do
        @cache_adapter.hash_delete(@cache_name, key, field, @adapter_opts)
      end

      def hash_values(key) do
        @cache_adapter.hash_values(@cache_name, key, @adapter_opts)
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
      strategy: :fifo
    ]
  end

  @impl Cache
  def put(pool_name, key, ttl, value, opts \\ []) do
    with {:ok, "OK"} <- command(pool_name, redis_set_command(pool_name, key, ttl, value), opts) do
      :ok
    end
  end

  defp redis_set_command(pool_name, key, _ttl, nil) do
    ["DEL", cache_key(pool_name, key)]
  end

  defp redis_set_command(pool_name, key, nil, value) do
    ["SET", cache_key(pool_name, key), value]
  end

  defp redis_set_command(pool_name, key, ttl, value) do
    key = cache_key(pool_name, key)

    ["SETEX", key, ms_to_nearest_sec(ttl), value]
  end

  def ms_to_nearest_sec(ms) do
    round(ms / :timer.seconds(1))
  end

  @impl Cache
  def get(pool_name, key, opts \\ []) do
    command(pool_name, ["GET", cache_key(pool_name, key)], opts)
  end

  @impl Cache
  def delete(pool_name, key, opts \\ []) do
    with {:ok, _} <- command(pool_name, ["DEL", cache_key(pool_name, key)], opts) do
      :ok
    end
  end

  def hash_get(pool_name, key, field, opts) do
    field = TermEncoder.encode(field, opts[:compression_level])

    with {:ok, value} when not is_nil(value) <-
           command(pool_name, ["HGET", cache_key(pool_name, key), field], opts) do
      {:ok, TermEncoder.decode(value)}
    end
  end

  def hash_get_all(pool_name, key, opts) do
    with {:ok, data} <- command(pool_name, ["HGETALL", cache_key(pool_name, key)], opts) do
      hash =
        data
        |> Enum.chunk_every(2)
        |> Map.new(fn [field, value] ->
          {TermEncoder.decode(field), TermEncoder.decode(value)}
        end)

      {:ok, hash}
    end
  end

  def hash_set(pool_name, key, field, value, opts) do
    field = TermEncoder.encode(field, opts[:compression_level])
    value = TermEncoder.encode(value, opts[:compression_level])

    command(pool_name, ["HSET", cache_key(pool_name, key), field, value], opts)
  end

  def hash_set_many(pool_name, key_values, ttl, opts) do
    commands =
      Enum.map(key_values, fn {key, field_values} ->
        field_values =
          field_values
          |> Enum.map(fn {field, value} ->
            [
              TermEncoder.encode(field, opts[:compression_level]),
              TermEncoder.encode(value, opts[:compression_level])
            ]
          end)
          |> List.flatten()

        ["HSET", cache_key(pool_name, key) | field_values]
      end)

    expiries =
      if ttl do
        Enum.map(key_values, fn {key, _} ->
          ["PEXPIRE", cache_key(pool_name, key), ttl]
        end)
      else
        []
      end

    pipeline(pool_name, commands ++ expiries, opts)
  end

  def hash_delete(pool_name, key, field, opts) do
    field = TermEncoder.encode(field, opts[:compression_level])
    command(pool_name, ["HDEL", cache_key(pool_name, key), field], opts)
  end

  def hash_values(pool_name, key, opts) do
    with {:ok, data} <- command(pool_name, ["HVALS", cache_key(pool_name, key)], opts) do
      values =
        Enum.map(data, fn value ->
          TermEncoder.decode(value)
        end)

      {:ok, values}
    end
  end

  defp cache_key(pool_name, key) do
    "#{pool_name}:#{key}"
  end

  def command(pool_name, command, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      pid |> Redix.command(command, opts) |> handle_response
    end)
  end

  def command!(pool_name, command, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      Redix.command!(pid, command, opts)
    end)
  end

  def pipeline(pool_name, commands, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      pid |> Redix.pipeline(commands, opts) |> handle_response
    end)
  end

  def pipeline!(pool_name, commands, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      Redix.pipeline!(pid, commands, opts)
    end)
  end

  defp handle_response({:ok, "OK"}), do: :ok
  defp handle_response({:ok, _} = res), do: res
  defp handle_response({:error, %Redix.ConnectionError{reason: reason}}) do
    {:error, ErrorMessage.service_unavailable("redis connection errored because: #{reason}")}
  end

  defp handle_response({:error, _} = res), do: res
end
