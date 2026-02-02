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
  DETS (Disk Erlang Term Storage) adapter for persistent disk-based caching.

  This adapter provides persistent storage using Erlang's DETS tables, which store data
  on disk. It's ideal for applications that need cache persistence across restarts.

  ## Features

  * Persistent disk-based storage
  * Survives application restarts
  * Direct access to DETS-specific operations
  * Configurable file path and table type

  ## Options
  #{NimbleOptions.docs(@opts_definition)}

  ## Example

      defmodule MyApp.PersistentCache do
        use Cache,
          adapter: Cache.DETS,
          name: :persistent_cache,
          opts: [
            file_path: "/tmp/cache",
            type: :set
          ]
      end

  ## Usage

      iex> {:ok, _pid} = Cache.DETS.start_link(table_name: :doctest_dets_cache, file_path: "/tmp")
      iex> Process.sleep(10)
      iex> Cache.DETS.put(:doctest_dets_cache, "key", nil, "value")
      :ok
      iex> Cache.DETS.get(:doctest_dets_cache, "key")
      {:ok, "value"}
      iex> Cache.DETS.delete(:doctest_dets_cache, "key")
      :ok
      iex> Cache.DETS.get(:doctest_dets_cache, "key")
      {:ok, nil}
  """

  use Task, restart: :permanent

  @behaviour Cache

  defmacro __using__(_opts) do
    quote do
      @doc """
      Returns a list of the names of all open DETS tables on this node.
      """
      def all do
        :dets.all()
      end

      @doc """
      Returns a list of objects stored in the table (binary chunk format).
      """
      def bchunk(continuation) do
        :dets.bchunk(@cache_name, continuation)
      end

      @doc """
      Closes the DETS table.
      """
      def close do
        :dets.close(@cache_name)
      end

      @doc """
      Deletes all objects in the DETS table.
      """
      def delete_all_objects do
        :dets.delete_all_objects(@cache_name)
      end

      @doc """
      Deletes the exact object from the DETS table.
      """
      def delete_object(object) do
        :dets.delete_object(@cache_name, object)
      end

      @doc """
      Returns the first key in the table.
      """
      def first do
        :dets.first(@cache_name)
      end

      @doc """
      Folds over all objects in the table.
      """
      def foldl(function, acc) do
        :dets.foldl(function, acc, @cache_name)
      end

      @doc """
      Folds over all objects in the table (same as foldl for DETS).
      """
      def foldr(function, acc) do
        :dets.foldr(function, acc, @cache_name)
      end

      @doc """
      Get information about the DETS table.
      """
      def info do
        :dets.info(@cache_name)
      end

      @doc """
      Get specific information about the DETS table.
      """
      def info(item) do
        :dets.info(@cache_name, item)
      end

      @doc """
      Replaces the existing objects of the table with objects created by calling the input function.
      """
      def init_table(init_fun) do
        :dets.init_table(@cache_name, init_fun)
      end

      @doc """
      Replaces the existing objects of the table with objects created by calling the input function with options.
      """
      def init_table(init_fun, options) do
        :dets.init_table(@cache_name, init_fun, options)
      end

      @doc """
      Insert raw data into the DETS table using the underlying :dets.insert/2 function.
      """
      def insert_raw(data) do
        :dets.insert(@cache_name, data)
      end

      @doc """
      Same as insert/2 except returns false if any object with the same key already exists.
      """
      def insert_new(data) do
        :dets.insert_new(@cache_name, data)
      end

      @doc """
      Returns true if it would be possible to initialize the table with bchunk data.
      """
      # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
      def is_compatible_bchunk_format(bchunk_format) do
        :dets.is_compatible_bchunk_format(@cache_name, bchunk_format)
      end

      @doc """
      Returns true if the file is a DETS table.
      """
      # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
      def is_dets_file(filename) do
        :dets.is_dets_file(filename)
      end

      @doc """
      Returns a list of all objects with the given key.
      """
      def lookup(key) do
        :dets.lookup(@cache_name, key)
      end

      @doc """
      Continues a match started with match/2.
      """
      def match(continuation) when not is_tuple(continuation) do
        :dets.match(continuation)
      end

      @doc """
      Matches the objects in the table against the pattern.
      """
      def match(pattern) do
        :dets.match(@cache_name, pattern)
      end

      @doc """
      Matches the objects in the table against the pattern with a limit.
      """
      def match(pattern, limit) do
        :dets.match(@cache_name, pattern, limit)
      end

      @doc """
      Deletes all objects that match the pattern from the table.
      """
      def match_delete(pattern) do
        :dets.match_delete(@cache_name, pattern)
      end

      @doc """
      Continues a match_object started with match_object/2.
      """
      def match_object(continuation) when not is_tuple(continuation) do
        :dets.match_object(continuation)
      end

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
      Returns the next key following the given key.
      """
      def next(key) do
        :dets.next(@cache_name, key)
      end

      @doc """
      Opens an existing DETS table file.
      """
      def open_file(filename) do
        :dets.open_file(filename)
      end

      @doc """
      Opens a DETS table with the given name and arguments.
      """
      def open_file(name, args) do
        :dets.open_file(name, args)
      end

      @doc """
      Returns the table name given the pid of a process that handles requests to a table.
      """
      def pid2name(pid) do
        :dets.pid2name(pid)
      end

      @doc """
      Restores an opaque continuation that has passed through external term format.
      """
      def repair_continuation(continuation, match_spec) do
        :dets.repair_continuation(continuation, match_spec)
      end

      @doc """
      Fixes the table for safe traversal.
      """
      def safe_fixtable(fix) do
        :dets.safe_fixtable(@cache_name, fix)
      end

      @doc """
      Continues a select started with select/2.
      """
      def select(continuation) when not is_list(continuation) do
        :dets.select(continuation)
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
      Delete objects from the DETS table using a match specification.
      """
      def select_delete(match_spec) do
        :dets.select_delete(@cache_name, match_spec)
      end

      @doc """
      Returns the list of objects associated with slot I.
      """
      def slot(i) do
        :dets.slot(@cache_name, i)
      end

      @doc """
      Ensures that all updates made to the table are written to disk.
      """
      def sync do
        :dets.sync(@cache_name)
      end

      @doc """
      Returns a QLC query handle for the table.
      """
      def table do
        :dets.table(@cache_name)
      end

      @doc """
      Returns a QLC query handle for the table with options.
      """
      def table(options) do
        :dets.table(@cache_name, options)
      end

      @doc """
      Applies a function to each object stored in the table.
      """
      def traverse(fun) do
        :dets.traverse(@cache_name, fun)
      end

      @doc """
      Update a counter in the DETS table.
      """
      def update_counter(key, update_op) do
        :dets.update_counter(@cache_name, key, update_op)
      end

      @doc """
      Convert a DETS table to the given ETS table.
      """
      def to_ets(ets_table) do
        :dets.to_ets(@cache_name, ets_table)
      end

      @doc """
      Convert an ETS table to a DETS table.
      """
      def from_ets(ets_table) do
        :dets.from_ets(@cache_name, ets_table)
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
