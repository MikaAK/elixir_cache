defmodule Cache.ETS do
  require Logger
  require Cache.OTPVersion

  @exit_signals [
    :sigabrt,
    :sigalrm,
    :sigchld,
    :sighup,
    :sigquit,
    :sigstop,
    :sigterm,
    :sigtstp,
    :sigusr1,
    :sigusr2
  ]

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
    ],
    store_on_exit_path: [
      type: :string,
      doc: "Path to store the ETS table on exit and rehydrate on startup"
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
  * Optional persistence via `store_on_exit_path` for rehydration on restart

  ## Options
  #{NimbleOptions.docs(@opts_definition)}

  ## Example

      defmodule MyApp.Cache do
        use Cache,
          adapter: Cache.ETS,
          name: :my_app_cache,
          opts: [
            read_concurrency: true,
            write_concurrency: true
          ]
      end

  ## Usage

      iex> {:ok, _pid} = Cache.ETS.start_link(table_name: :doctest_ets_cache, type: :set)
      iex> Process.sleep(10)
      iex> Cache.ETS.put(:doctest_ets_cache, "key", nil, "value")
      :ok
      iex> Cache.ETS.get(:doctest_ets_cache, "key")
      {:ok, "value"}
      iex> Cache.ETS.delete(:doctest_ets_cache, "key")
      :ok
      iex> Cache.ETS.get(:doctest_ets_cache, "key")
      {:ok, nil}
  """

  use Task, restart: :permanent

  @behaviour Cache

  defmacro __using__(_opts) do
    quote do
      require Cache.OTPVersion

      @doc """
      Returns a list of all ETS tables at the node.
      """
      def all do
        :ets.all()
      end

      @doc """
      Deletes the entire ETS table.
      """
      def delete_table do
        :ets.delete(@cache_name)
      end

      @doc """
      Deletes all objects in the ETS table.
      """
      def delete_all_objects do
        :ets.delete_all_objects(@cache_name)
      end

      @doc """
      Deletes the exact object from the ETS table.
      """
      def delete_object(object) do
        :ets.delete_object(@cache_name, object)
      end

      @doc """
      Reads a file produced by tab2file/1,2 and creates the corresponding table.
      """
      def file2tab(filename) do
        :ets.file2tab(filename)
      end

      @doc """
      Reads a file produced by tab2file/1,2 and creates the corresponding table with options.
      """
      def file2tab(filename, options) do
        :ets.file2tab(filename, options)
      end

      @doc """
      Returns the first key in the table.
      """
      def first do
        :ets.first(@cache_name)
      end

      if Cache.OTPVersion.otp_release_at_least?(26) do
        @doc """
        Returns the first key and object(s) in the table. (OTP 26+)
        """
        def first_lookup do
          :ets.first_lookup(@cache_name)
        end
      end

      @doc """
      Folds over all objects in the table from first to last.
      """
      def foldl(function, acc) do
        :ets.foldl(function, acc, @cache_name)
      end

      @doc """
      Folds over all objects in the table from last to first.
      """
      def foldr(function, acc) do
        :ets.foldr(function, acc, @cache_name)
      end

      @doc """
      Makes process pid the new owner of the table.
      """
      def give_away(pid, gift_data) do
        :ets.give_away(@cache_name, pid, gift_data)
      end

      @doc """
      Get information about the ETS table.
      """
      def info do
        :ets.info(@cache_name)
      end

      @doc """
      Get specific information about the ETS table.
      """
      def info(item) do
        :ets.info(@cache_name, item)
      end

      @doc """
      Replaces the existing objects of the table with objects created by calling the input function.
      """
      def init_table(init_fun) do
        :ets.init_table(@cache_name, init_fun)
      end

      @doc """
      Insert raw data into the ETS table using the underlying :ets.insert/2 function.
      """
      def insert_raw(data) do
        :ets.insert(@cache_name, data)
      end

      @doc """
      Same as insert/2 except returns false if any object with the same key already exists.
      """
      def insert_new(data) do
        :ets.insert_new(@cache_name, data)
      end

      @doc """
      Checks if a term represents a valid compiled match specification.
      """
      # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
      def is_compiled_ms(term) do
        :ets.is_compiled_ms(term)
      end

      @doc """
      Returns the last key in the table (for ordered_set, otherwise same as first).
      """
      def last do
        :ets.last(@cache_name)
      end

      if Cache.OTPVersion.otp_release_at_least?(26) do
        @doc """
        Returns the last key and object(s) in the table. (OTP 26+)
        """
        def last_lookup do
          :ets.last_lookup(@cache_name)
        end
      end

      @doc """
      Returns a list of all objects with the given key.
      """
      def lookup(key) do
        :ets.lookup(@cache_name, key)
      end

      @doc """
      Returns the Pos:th element of the object with the given key.
      """
      def lookup_element(key, pos) do
        :ets.lookup_element(@cache_name, key, pos)
      end

      if Cache.OTPVersion.otp_release_at_least?(26) do
        @doc """
        Returns the Pos:th element of the object with the given key, or default if not found. (OTP 26+)
        """
        def lookup_element(key, pos, default) do
          :ets.lookup_element(@cache_name, key, pos, default)
        end
      end

      @doc """
      Continues a match started with match/2.
      """
      def match(continuation) do
        :ets.match(continuation)
      end

      @doc """
      Matches the objects in the table against the pattern.
      """
      def match_pattern(pattern) do
        :ets.match(@cache_name, pattern)
      end

      @doc """
      Matches the objects in the table against the pattern with a limit.
      """
      def match_pattern(pattern, limit) do
        :ets.match(@cache_name, pattern, limit)
      end

      @doc """
      Deletes all objects that match the pattern from the table.
      """
      def match_delete(pattern) do
        :ets.match_delete(@cache_name, pattern)
      end

      @doc """
      Continues a match_object started with match_object/2.
      """
      def match_object(continuation) when not is_tuple(continuation) do
        :ets.match_object(continuation)
      end

      @doc """
      Match objects in the ETS table that match the given pattern.
      """
      def match_object(pattern) do
        :ets.match_object(@cache_name, pattern)
      end

      @doc """
      Match objects in the ETS table that match the given pattern with limit.
      """
      def match_object(pattern, limit) do
        :ets.match_object(@cache_name, pattern, limit)
      end

      @doc """
      Transforms a match specification into an internal representation.
      """
      def match_spec_compile(match_spec) do
        :ets.match_spec_compile(match_spec)
      end

      @doc """
      Executes the matching specified in a compiled match specification on a list of terms.
      """
      def match_spec_run(list, compiled_match_spec) do
        :ets.match_spec_run(list, compiled_match_spec)
      end

      @doc """
      Check if a key is a member of the ETS table.
      """
      def member(key) do
        :ets.member(@cache_name, key)
      end

      @doc """
      Returns the next key following the given key.
      """
      def next(key) do
        :ets.next(@cache_name, key)
      end

      if Cache.OTPVersion.otp_release_at_least?(26) do
        @doc """
        Returns the next key and object(s) following the given key. (OTP 26+)
        """
        def next_lookup(key) do
          :ets.next_lookup(@cache_name, key)
        end
      end

      @doc """
      Returns the previous key preceding the given key (for ordered_set).
      """
      def prev(key) do
        :ets.prev(@cache_name, key)
      end

      if Cache.OTPVersion.otp_release_at_least?(26) do
        @doc """
        Returns the previous key and object(s) preceding the given key. (OTP 26+)
        """
        def prev_lookup(key) do
          :ets.prev_lookup(@cache_name, key)
        end
      end

      @doc """
      Renames the table to the new name.
      """
      def rename(name) do
        :ets.rename(@cache_name, name)
      end

      @doc """
      Restores an opaque continuation that has passed through external term format.
      """
      def repair_continuation(continuation, match_spec) do
        :ets.repair_continuation(continuation, match_spec)
      end

      @doc """
      Fixes the table for safe traversal.
      """
      def safe_fixtable(fix) do
        :ets.safe_fixtable(@cache_name, fix)
      end

      @doc """
      Continues a select started with select/2.
      """
      def select(continuation) when not is_list(continuation) do
        :ets.select(continuation)
      end

      @doc """
      Select objects from the ETS table using a match specification.
      """
      def select(match_spec) do
        :ets.select(@cache_name, match_spec)
      end

      @doc """
      Select objects from the ETS table using a match specification with limit.
      """
      def select(match_spec, limit) do
        :ets.select(@cache_name, match_spec, limit)
      end

      @doc """
      Counts the objects matching the match specification.
      """
      def select_count(match_spec) do
        :ets.select_count(@cache_name, match_spec)
      end

      @doc """
      Delete objects from the ETS table using a match specification.
      """
      def select_delete(match_spec) do
        :ets.select_delete(@cache_name, match_spec)
      end

      @doc """
      Replaces objects matching the match specification with the match specification result.
      """
      def select_replace(match_spec) do
        :ets.select_replace(@cache_name, match_spec)
      end

      @doc """
      Continues a select_reverse started with select_reverse/2.
      """
      def select_reverse(continuation) when not is_list(continuation) do
        :ets.select_reverse(continuation)
      end

      @doc """
      Like select/1 but returns the list in reverse order for ordered_set.
      """
      def select_reverse(match_spec) do
        :ets.select_reverse(@cache_name, match_spec)
      end

      @doc """
      Like select/2 but traverses in reverse order for ordered_set.
      """
      def select_reverse(match_spec, limit) do
        :ets.select_reverse(@cache_name, match_spec, limit)
      end

      @doc """
      Sets table options (only heir is allowed after creation).
      """
      def setopts(opts) do
        :ets.setopts(@cache_name, opts)
      end

      @doc """
      Returns the list of objects associated with slot I.
      """
      def slot(i) do
        :ets.slot(@cache_name, i)
      end

      @doc """
      Dumps the table to a file.
      """
      def tab2file(filename) do
        :ets.tab2file(@cache_name, filename)
      end

      @doc """
      Dumps the table to a file with options.
      """
      def tab2file(filename, options) do
        :ets.tab2file(@cache_name, filename, options)
      end

      @doc """
      Returns a list of all objects in the table.
      """
      def tab2list do
        :ets.tab2list(@cache_name)
      end

      @doc """
      Returns information about the table dumped to file.
      """
      def tabfile_info(filename) do
        :ets.tabfile_info(filename)
      end

      @doc """
      Returns a QLC query handle for the table.
      """
      def table do
        :ets.table(@cache_name)
      end

      @doc """
      Returns a QLC query handle for the table with options.
      """
      def table(options) do
        :ets.table(@cache_name, options)
      end

      @doc """
      Returns and removes all objects with the given key.
      """
      def take(key) do
        :ets.take(@cache_name, key)
      end

      @doc """
      Tests a match specification against a tuple.
      """
      def test_ms(tuple, match_spec) do
        :ets.test_ms(tuple, match_spec)
      end

      @doc """
      Update a counter in the ETS table.
      """
      def update_counter(key, update_op) do
        :ets.update_counter(@cache_name, key, update_op)
      end

      @doc """
      Update a counter in the ETS table with a default value.
      """
      def update_counter(key, update_op, default) do
        :ets.update_counter(@cache_name, key, update_op, default)
      end

      @doc """
      Updates specific elements of an object.
      """
      def update_element(key, element_spec) do
        :ets.update_element(@cache_name, key, element_spec)
      end

      if Cache.OTPVersion.otp_release_at_least?(26) do
        @doc """
        Updates specific elements of an object with a default. (OTP 26+)
        """
        def update_element(key, element_spec, default) do
          :ets.update_element(@cache_name, key, element_spec, default)
        end
      end

      @doc """
      Returns the tid of this named table.
      """
      def whereis do
        :ets.whereis(@cache_name)
      end

      @doc """
      Convert an ETS table to a DETS table.
      """
      def to_dets(dets_table) do
        :ets.to_dets(@cache_name, dets_table)
      end

      @doc """
      Convert a DETS table to an ETS table.
      """
      def from_dets(dets_table) do
        :ets.from_dets(@cache_name, dets_table)
      end
    end
  end

  @impl Cache
  def opts_definition, do: @opts_definition

  @impl Cache
  def start_link(opts) do
    Task.start_link(fn ->
      table_name = opts[:table_name]
      store_on_exit_path = opts[:store_on_exit_path]

      ets_opts =
        opts
        |> Keyword.drop([:table_name, :type, :store_on_exit_path])
        |> Kernel.++([opts[:type], :public, :named_table])

      ets_opts =
        if opts[:compressed] do
          Keyword.delete(ets_opts, :compressed) ++ [:compressed]
        else
          ets_opts
        end

      rehydrate_or_create_table(table_name, store_on_exit_path, ets_opts)

      if store_on_exit_path do
        setup_exit_signal_handlers(table_name, store_on_exit_path)
      end

      Process.hibernate(Function, :identity, [nil])
    end)
  end

  defp rehydrate_or_create_table(table_name, store_on_exit_path, ets_opts)
       when is_binary(store_on_exit_path) do
    file_path = build_file_path(table_name, store_on_exit_path)

    if File.exists?(file_path) do
      case :ets.file2tab(String.to_charlist(file_path)) do
        {:ok, ^table_name} ->
          Logger.info("[Cache.ETS] Rehydrated #{table_name} from #{file_path}")
          :ok

        {:ok, _other_name} ->
          Logger.warning("[Cache.ETS] File #{file_path} has different table name, creating new table #{table_name}")
          :ets.new(table_name, ets_opts)

        {:error, reason} ->
          Logger.warning("[Cache.ETS] Failed to rehydrate #{table_name} from #{file_path}: #{inspect(reason)}, creating new table")
          :ets.new(table_name, ets_opts)
      end
    else
      :ets.new(table_name, ets_opts)
    end
  end

  defp rehydrate_or_create_table(table_name, _store_on_exit_path, ets_opts) do
    :ets.new(table_name, ets_opts)
  end

  defp setup_exit_signal_handlers(table_name, store_on_exit_path) do
    file_path = build_file_path(table_name, store_on_exit_path)

    Enum.each(@exit_signals, fn signal ->
      case System.trap_signal(signal, fn ->
             :ets.tab2file(table_name, String.to_charlist(file_path))
             :ok
           end) do
        {:ok, _ref} -> :ok
        {:error, reason} ->
          Logger.error("[Cache.ETS] Failed to setup exit signal handler for #{table_name}: #{inspect(reason)}")

          :ok
      end
    end)
  end

  defp build_file_path(table_name, store_on_exit_path) do
    Path.join(store_on_exit_path, "#{table_name}.ets")
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
