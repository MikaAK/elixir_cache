defmodule Cache.ETS do
  @opts_definition [
    write_concurrency: [
      type: :boolean,
      doc: "Enable write concurrency"
    ],
    read_concurrency: [
      type: :boolean,
      doc: "Enable read concurrency"
    ],
    decentralized_counters: [
      type: :boolean,
      doc: "Use decentralized counters"
    ],
    type: [
      type: {:in, [:bag, :duplicate_bag, :set]},
      default: :set,
      doc: "Data type of ETS cache"
    ],
    compressed: [
      type: :boolean,
      doc: "Enable ets compression"
    ]
  ]

  @moduledoc """
  ETS (Erlang Term Storage) adapter for high-performance in-memory caching.

  This adapter provides a fast, process-independent cache using Erlang's built-in ETS tables.
  It's ideal for applications requiring low-latency access to cached data within a single node.

  ## Features

  * In-memory storage with configurable concurrency options
  * Direct access to ETS-specific operations
  * Very high performance for read and write operations
  * Support for atomic counter operations

  ## Options
  #{NimbleOptions.docs(@opts_definition)}

  ## Example

  ```elixir
  defmodule MyApp.Cache do
    use Cache,
      adapter: Cache.ETS,
      name: :my_app_cache,
      opts: [
        read_concurrency: true,
        write_concurrency: true
      ]
  end
  ```
  """

  use Task, restart: :permanent

  @behaviour Cache

  defmacro __using__(_opts) do
    quote do
      @doc """
      Match objects in the ETS table that match the given pattern.

      ## Examples

          iex> #{inspect(__MODULE__)}.match_object({:_, :_})
          [...]
      """
      def match_object(pattern) do
        :ets.match_object(@cache_name, pattern)
      end

      @doc """
      Match objects in the ETS table that match the given pattern with limit.

      ## Examples

          iex> #{inspect(__MODULE__)}.match_object({:_, :_}, 10)
          {[...], continuation}
      """
      def match_object(pattern, limit) do
        :ets.match_object(@cache_name, pattern, limit)
      end

      @doc """
      Check if a key is a member of the ETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.member(:key)
          true
      """
      def member(key) do
        :ets.member(@cache_name, key)
      end

      @doc """
      Select objects from the ETS table using a match specification.

      ## Examples

          iex> #{inspect(__MODULE__)}.select([{{:key, :_}, [], [:'$_']}])
          [...]
      """
      def select(match_spec) do
        :ets.select(@cache_name, match_spec)
      end

      @doc """
      Select objects from the ETS table using a match specification with limit.

      ## Examples

          iex> #{inspect(__MODULE__)}.select([{{:key, :_}, [], [:'$_']}], 10)
          {[...], continuation}
      """
      def select(match_spec, limit) do
        :ets.select(@cache_name, match_spec, limit)
      end

      @doc """
      Get information about the ETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.info()
          [...]
      """
      def info do
        :ets.info(@cache_name)
      end

      @doc """
      Get specific information about the ETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.info(:size)
          42
      """
      def info(item) do
        :ets.info(@cache_name, item)
      end

      @doc """
      Delete objects from the ETS table using a match specification.

      ## Examples

          iex> #{inspect(__MODULE__)}.select_delete([{{:key, :_}, [], [true]}])
          42
      """
      def select_delete(match_spec) do
        :ets.select_delete(@cache_name, match_spec)
      end

      @doc """
      Delete objects from the ETS table that match the given pattern.

      ## Examples

          iex> #{inspect(__MODULE__)}.match_delete({:key, :_})
          true
      """
      def match_delete(pattern) do
        :ets.match_delete(@cache_name, pattern)
      end

      @doc """
      Update a counter in the ETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.update_counter(:counter_key, {2, 1})
          43
      """
      def update_counter(key, update_op) do
        :ets.update_counter(@cache_name, key, update_op)
      end

      @doc """
      Insert raw data into the ETS table using the underlying :ets.insert/2 function.

      ## Examples

          iex> #{inspect(__MODULE__)}.insert_raw({:key, "value"})
          true
          iex> #{inspect(__MODULE__)}.insert_raw([{:key1, "value1"}, {:key2, "value2"}])
          true
      """
      def insert_raw(data) do
        :ets.insert(@cache_name, data)
      end

      if function_exported?(:ets, :to_dets, 1) do
        @doc """
        Convert an ETS table to a DETS table.

        ## Examples

            iex> #{inspect(__MODULE__)}.to_dets(:my_dets_table)
            :ok
        """
        def to_dets(dets_table) do
          :ets.to_dets(@cache_name, dets_table)
        end

        @doc """
        Convert a DETS table to an ETS table.

        ## Examples

            iex> #{inspect(__MODULE__)}.from_dets(:my_dets_table)
            :ok
        """
        def from_dets(dets_table) do
          :ets.from_dets(@cache_name, dets_table)
        end
      end
    end
  end

  @impl Cache
  def opts_definition, do: @opts_definition

  def opts_definition(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      validate_and_normalize_ets_options(opts)
    else
      {:error, "expected a keyword list"}
    end
  end

  def opts_definition(_opts), do: {:error, "expected a keyword list"}

  defp validate_and_normalize_ets_options(opts) do
    case NimbleOptions.validate(opts, @opts_definition) do
      {:ok, validated} ->
        {:ok, normalize_ets_options(opts, validated)}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  defp normalize_ets_options(original_opts, validated) do
    Enum.reject(
      [
        maybe_type(original_opts, validated),
        maybe_compressed(original_opts, validated),
        maybe_kv(original_opts, validated, :read_concurrency),
        maybe_kv(original_opts, validated, :write_concurrency),
        maybe_kv(original_opts, validated, :decentralized_counters)
      ],
      &is_nil/1
    )
  end

  defp maybe_type(original_opts, validated) do
    if Keyword.has_key?(original_opts, :type), do: validated[:type]
  end

  defp maybe_compressed(original_opts, validated) do
    if Keyword.has_key?(original_opts, :compressed) and validated[:compressed], do: :compressed
  end

  defp maybe_kv(original_opts, validated, key) do
    if Keyword.has_key?(original_opts, key), do: {key, validated[key]}
  end

  @impl Cache
  def start_link(opts) do
    Task.start_link(fn ->
      table_name = opts[:table_name]

      opts =
        opts
        |> Keyword.drop([:table_name, :type])
        |> Kernel.++([opts[:type], :public, :named_table])

      opts =
        if opts[:compressed] do
          Keyword.delete(opts, :compressed) ++ [:compressed]
        else
          opts
        end

      _ = :ets.new(table_name, opts)

      Process.hibernate(Function, :identity, [nil])
    end)
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: "#{cache_name}_elixir_cache_ets",
      start: {Cache.ETS, :start_link, [Keyword.put(opts, :table_name, cache_name)]}
    }
  end

  @impl Cache
  def get(cache_name, key, _opts \\ []) do
    case :ets.lookup(cache_name, key) do
      [{^key, value}] -> {:ok, value}
      # This can happen if someone uses insert_raw
      [value] -> {:ok, value}
      [] -> {:ok, nil}
    end
  end

  @impl Cache
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ []) do
    :ets.insert(cache_name, {key, value})

    :ok
  end

  @impl Cache
  def delete(cache_name, key, _opts \\ []) do
    :ets.delete(cache_name, key)

    :ok
  end
end
