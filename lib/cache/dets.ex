defmodule Cache.DETS do
  @opts_definition [
    ram_file: [
      type: :boolean,
      default: false,
      doc: "Enable RAM File"
    ],
    type: [
      type: {:in, [:bag, :duplicate_bag, :set]},
      default: :set,
      doc: "Data type of DETS cache"
    ],
    file_path: [
      type: :string,
      default: "./",
      doc: "File path to save DETS file at"
    ]
  ]

  @moduledoc """
  DETS adapter so that we can use dets as a cache

  ## Options
  #{NimbleOptions.docs(@opts_definition)}
  """

  use Task, restart: :permanent

  @behaviour Cache

  defmacro __using__(_opts) do
    quote do
      @doc """
      Match objects in the DETS table that match the given pattern.

      ## Examples

          iex> #{inspect(__MODULE__)}.match_object({:_, :_})
          [...]
      """
      def match_object(pattern) do
        :dets.match_object(@cache_name, pattern)
      end

      @doc """
      Match objects in the DETS table that match the given pattern with limit.

      ## Examples

          iex> #{inspect(__MODULE__)}.match_object({:_, :_}, 10)
          {[...], continuation}
      """
      def match_object(pattern, limit) do
        :dets.match_object(@cache_name, pattern, limit)
      end

      @doc """
      Check if a key is a member of the DETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.member(:key)
          true
      """
      def member(key) do
        :dets.member(@cache_name, key)
      end

      @doc """
      Select objects from the DETS table using a match specification.

      ## Examples

          iex> #{inspect(__MODULE__)}.select([{{:key, :_}, [], [:'$_']}])
          [...]
      """
      def select(match_spec) do
        :dets.select(@cache_name, match_spec)
      end

      @doc """
      Select objects from the DETS table using a match specification with limit.

      ## Examples

          iex> #{inspect(__MODULE__)}.select([{{:key, :_}, [], [:'$_']}], 10)
          {[...], continuation}
      """
      def select(match_spec, limit) do
        :dets.select(@cache_name, match_spec, limit)
      end

      @doc """
      Get information about the DETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.info()
          [...]
      """
      def info do
        :dets.info(@cache_name)
      end

      @doc """
      Get specific information about the DETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.info(:size)
          42
      """
      def info(item) do
        :dets.info(@cache_name, item)
      end

      @doc """
      Delete objects from the DETS table using a match specification.

      ## Examples

          iex> #{inspect(__MODULE__)}.select_delete([{{:key, :_}, [], [true]}])
          42
      """
      def select_delete(match_spec) do
        :dets.select_delete(@cache_name, match_spec)
      end

      @doc """
      Delete objects from the DETS table that match the given pattern.

      ## Examples

          iex> #{inspect(__MODULE__)}.match_delete({:key, :_})
          :ok
      """
      def match_delete(pattern) do
        :dets.match_delete(@cache_name, pattern)
      end

      @doc """
      Update a counter in the DETS table.

      ## Examples

          iex> #{inspect(__MODULE__)}.update_counter(:counter_key, {2, 1})
          43
      """
      def update_counter(key, update_op) do
        :dets.update_counter(@cache_name, key, update_op)
      end

      @doc """
      Insert raw data into the DETS table using the underlying :dets.insert/2 function.

      ## Examples

          iex> #{inspect(__MODULE__)}.insert_raw({:key, "value"})
          :ok
          iex> #{inspect(__MODULE__)}.insert_raw([{:key1, "value1"}, {:key2, "value2"}])
          :ok
      """
      def insert_raw(data) do
        :dets.insert(@cache_name, data)
      end

      if function_exported?(:dets, :to_ets, 1) do
        @doc """
        Convert a DETS table to an ETS table.

        ## Examples

          iex> #{inspect(__MODULE__)}.to_ets()
          :my_ets_table
        """
        def to_ets do
          :dets.to_ets(@cache_name)
        end

        @doc """
        Convert an ETS table to a DETS table.

        ## Examples

            iex> #{inspect(__MODULE__)}.from_ets(:my_ets_table)
            :ok
        """
        def from_ets(ets_table) do
          :dets.from_ets(@cache_name, ets_table)
        end
      end
    end
  end

  @impl Cache
  def opts_definition, do: @opts_definition

  @impl Cache
  def start_link(opts) do
    Task.start_link(fn ->
      table_name = opts[:table_name]

      file_path =
        opts[:file_path]
        |> to_string
        |> create_file_name(table_name)
        |> tap(&File.mkdir_p!(Path.dirname(&1)))
        |> String.to_charlist()

      opts =
        opts
        |> Keyword.drop([:table_name, :file_path])
        |> Kernel.++(access: :read_write, file: file_path)

      {:ok, _} = :dets.open_file(table_name, opts)

      Process.hibernate(Function, :identity, [nil])
    end)
  end

  defp create_file_name(file_path, table_name) do
    if File.dir?(file_path) do
      Path.join(file_path, "#{table_name}.dets")
    else
      file_path
    end
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: "#{cache_name}_elixir_cache_dets",
      start: {Cache.DETS, :start_link, [Keyword.put(opts, :table_name, cache_name)]}
    }
  end

  @impl Cache
  def get(cache_name, key, _opts \\ []) do
    case :dets.lookup(cache_name, key) do
      [{^key, value}] -> {:ok, value}
      # This can happen if someone uses insert_raw
      [value] -> {:ok, value}
      [] -> {:ok, nil}
    end
  end

  @impl Cache
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ []) do
    :dets.insert(cache_name, {key, value})
  end

  @impl Cache
  def delete(cache_name, key, _opts \\ []) do
    :dets.delete(cache_name, key)
  end
end
