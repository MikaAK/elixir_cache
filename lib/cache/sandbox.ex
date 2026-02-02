defmodule Cache.Sandbox do
  @moduledoc """
  Sandbox adapter for isolated testing of applications using ElixirCache.

  This module provides a mock implementation of all cache adapters, allowing tests to run in isolation
  without interfering with each other's data. The sandbox uses a basic `Agent` to store data in memory
  and implements the full range of caching operations supported by all adapters.

  ## Features

  * Isolated cache namespaces for concurrent testing
  * Support for all standard cache operations
  * Implementation of Redis-specific features like hash and JSON operations
  * Implementation of ETS-specific operations for complete testing compatibility
  * Lightweight in-memory storage for fast test execution

  ## Usage

  The Sandbox adapter is typically enabled through the `sandbox?` option when defining a cache module:

      defmodule MyApp.TestCache do
        use Cache,
          adapter: Cache.Redis,
          name: :test_cache,
          opts: [],
          sandbox?: Mix.env() == :test
      end

  In your tests, use `Cache.SandboxRegistry.start(MyApp.TestCache)` in the setup block to ensure
  proper isolation between test cases.

  > **Note**: This adapter should not be used in production environments.

  ## Basic Operations

      iex> {:ok, _pid} = Cache.Sandbox.start_link(name: :test_sandbox_cache)
      iex> Cache.Sandbox.put(:test_sandbox_cache, "key", nil, "value")
      :ok
      iex> Cache.Sandbox.get(:test_sandbox_cache, "key")
      {:ok, "value"}
      iex> Cache.Sandbox.delete(:test_sandbox_cache, "key")
      :ok
      iex> Cache.Sandbox.get(:test_sandbox_cache, "key")
      {:ok, nil}
  """

  use Agent

  alias Cache.Redis.JSON
  alias Cache.TermEncoder

  @behaviour Cache

  @impl Cache
  def opts_definition, do: []

  @impl Cache
  def start_link(opts \\ []) do
    with {:error, {:already_started, pid}} <- Agent.start_link(fn -> %{} end, opts) do
      {:ok, pid}
    end
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: "#{cache_name}_elixir_cache_agent",
      start: {__MODULE__, :start_link, [Keyword.put(opts, :name, cache_name)]}
    }
  end

  @impl Cache
  def get(cache_name, key, _opts \\ []) do
    Agent.get(cache_name, fn state ->
      {:ok, Map.get(state, key)}
    end)
  end

  @impl Cache
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ []) do
    Agent.update(cache_name, fn state ->
      Map.put(state, key, value)
    end)
  end

  @impl Cache
  def delete(cache_name, key, _opts \\ []) do
    Agent.update(cache_name, fn state ->
      Map.delete(state, key)
    end)
  end

  def hash_delete(cache_name, key, hash_key, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(state, key, %{}, &Map.delete(&1, hash_key))
    end)
  end

  def hash_get(cache_name, key, hash_key, _opts) do
    Agent.get(cache_name, fn state ->
      {:ok, state[key][hash_key]}
    end)
  end

  def hash_get_all(cache_name, key, _opts) do
    Agent.get(cache_name, fn state ->
      case state[key] do
        nil -> {:ok, %{}}
        value -> {:ok, value}
      end
    end)
  end

  def hash_get_many(cache_name, keys_fields, _opts) do
    Agent.get(cache_name, fn state ->
      values =
        Enum.reduce(keys_fields, [], fn {key, fields}, acc ->
          values = Enum.map(fields, &state[key][&1])
          acc ++ [values]
        end)

      {:ok, values}
    end)
  end

  def hash_values(cache_name, key, _opts) do
    Agent.get(cache_name, fn state ->
      {:ok, Map.values(state[key] || %{})}
    end)
  end

  def hash_set(cache_name, key, field, value, ttl, _opts) do
    Agent.update(cache_name, fn state ->
      put_hash_field_values(state, key, [{field, value}])
    end)

    if ttl do
      {:ok, [1, 1]}
    else
      :ok
    end
  end

  def hash_set_many(cache_name, keys_fields_values, ttl, _opts) do
    Agent.update(cache_name, fn state ->
      Enum.reduce(keys_fields_values, state, fn {key, fields_values}, acc ->
        put_hash_field_values(acc, key, fields_values)
      end)
    end)

    if ttl do
      command_resps =
        Enum.map(keys_fields_values, fn {_, fields_values} -> enum_length(fields_values) end)

      expiry_resps = Enum.map(keys_fields_values, fn _ -> 1 end)
      {:ok, command_resps ++ expiry_resps}
    else
      :ok
    end
  end

  def json_get(cache_name, key, path, _opts) when path in [nil, ["."]] do
    get(cache_name, key)
  end

  def json_get(cache_name, key, path, _opts) do
    if contains_index?(path) do
      [index | path] = Enum.reverse(path)

      with {:ok, value} <- serialize_path_and_get_value(cache_name, key, path) do
        {:ok, Enum.at(value, index)}
      end
    else
      serialize_path_and_get_value(cache_name, key, path)
    end
  end

  def json_set(cache_name, key, path, value, _opts) when path in [nil, ["."]] do
    put(cache_name, key, stringify_value(value))
  end

  def json_set(cache_name, key, path, value, _opts) do
    state = Agent.get(cache_name, & &1)
    path = JSON.serialize_path(path)

    with :ok <- check_key_exists(state, key),
         :ok <- check_path_exists(state, key, path) do
      path = add_defaults([key | String.split(path, ".")])
      value = stringify_value(value)

      Agent.update(cache_name, fn state ->
        put_in(state, path, value)
      end)
    end
  end

  def json_incr(cache_name, key, path, incr \\ 1, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(state, key, nil, fn value ->
        update_in(value, String.split(path), &(&1 + incr))
      end)
    end)
  end

  def json_clear(cache_name, key, path, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(
        state,
        key,
        nil,
        &update_in(&1, String.split(path, "."), fn
          integer when is_integer(integer) -> 0
          list when is_list(list) -> []
          map when is_map(map) -> %{}
          _ -> nil
        end)
      )
    end)
  end

  def json_delete(cache_name, key, path, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(state, key, nil, fn value ->
        {_, state} = pop_in(value, String.split(path, "."))

        state
      end)
    end)
  end

  def json_array_append(cache_name, key, path, value, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(state, key, nil, fn state_value ->
        update_in(state_value, String.split(path, "."), &(&1 ++ [value]))
      end)
    end)
  end

  # Redis Compatibility
  def pipeline(_cache_name, _commands, _opts) do
    raise "Not Implemented"
  end

  def pipeline!(_cache_name, _commands, _opts) do
    raise "Not Implemented"
  end

  def command(_cache_name, _command, _opts) do
    raise "Not Implemented"
  end

  def command!(_cache_name, _command, _opts) do
    raise "Not Implemented"
  end

  def scan(cache_name, _scan_opts, _opts) do
    Agent.get(cache_name, fn state ->
      {:ok, Map.keys(state)}
    end)
  end

  def hash_scan(cache_name, key, _scan_opts, _opts) do
    Agent.get(cache_name, fn state ->
      case Map.get(state, key) do
        nil -> {:ok, []}
        map when is_map(map) -> {:ok, Map.keys(map)}
        _ -> {:ok, []}
      end
    end)
  end

  # ETS & DETS Compatibility

  def all do
    Agent.get(Cache.Sandbox, fn state -> Map.keys(state) end)
  rescue
    _ -> []
  end

  def delete_table(cache_name) do
    Agent.update(cache_name, fn _ -> %{} end)
    true
  end

  def delete_all_objects(cache_name) do
    Agent.update(cache_name, fn _ -> %{} end)
    true
  end

  def delete_object(cache_name, object) when is_tuple(object) do
    key = elem(object, 0)

    Agent.update(cache_name, fn state ->
      case Map.get(state, key) do
        ^object -> Map.delete(state, key)
        _ -> state
      end
    end)

    true
  end

  def first(cache_name) do
    Agent.get(cache_name, fn state ->
      case Map.keys(state) do
        [] -> :"$end_of_table"
        [key | _] -> key
      end
    end)
  end

  def first_lookup(cache_name) do
    Agent.get(cache_name, fn state ->
      case Map.to_list(state) do
        [] -> :"$end_of_table"
        [{key, value} | _] -> {key, [{key, value}]}
      end
    end)
  end

  def last(cache_name) do
    Agent.get(cache_name, fn state ->
      case state |> Map.keys() |> Enum.reverse() do
        [] -> :"$end_of_table"
        [key | _] -> key
      end
    end)
  end

  def last_lookup(cache_name) do
    Agent.get(cache_name, fn state ->
      case state |> Map.to_list() |> Enum.reverse() do
        [] -> :"$end_of_table"
        [{key, value} | _] -> {key, [{key, value}]}
      end
    end)
  end

  def next(cache_name, key) do
    Agent.get(cache_name, fn state ->
      keys = state |> Map.keys() |> Enum.sort()
      find_next_key(keys, key)
    end)
  end

  def next_lookup(cache_name, key) do
    Agent.get(cache_name, fn state ->
      keys = state |> Map.keys() |> Enum.sort()

      case find_next_key(keys, key) do
        :"$end_of_table" -> :"$end_of_table"
        next_key -> {next_key, [{next_key, Map.get(state, next_key)}]}
      end
    end)
  end

  def prev(cache_name, key) do
    Agent.get(cache_name, fn state ->
      keys = state |> Map.keys() |> Enum.sort() |> Enum.reverse()
      find_next_key(keys, key)
    end)
  end

  def prev_lookup(cache_name, key) do
    Agent.get(cache_name, fn state ->
      keys = state |> Map.keys() |> Enum.sort() |> Enum.reverse()

      case find_next_key(keys, key) do
        :"$end_of_table" -> :"$end_of_table"
        prev_key -> {prev_key, [{prev_key, Map.get(state, prev_key)}]}
      end
    end)
  end

  defp find_next_key([], _key), do: :"$end_of_table"
  defp find_next_key([_], _key), do: :"$end_of_table"

  defp find_next_key([current, next | _rest], key) when current === key do
    next
  end

  defp find_next_key([_ | rest], key), do: find_next_key(rest, key)

  def foldl(cache_name, function, acc) do
    Agent.get(cache_name, fn state ->
      state
      |> Map.to_list()
      |> Enum.reduce(acc, fn {key, value}, acc_inner ->
        function.({key, value}, acc_inner)
      end)
    end)
  end

  def foldr(cache_name, function, acc) do
    Agent.get(cache_name, fn state ->
      state
      |> Map.to_list()
      |> Enum.reverse()
      |> Enum.reduce(acc, fn {key, value}, acc_inner ->
        function.({key, value}, acc_inner)
      end)
    end)
  end

  def member(cache_name, key) do
    Agent.get(cache_name, fn state ->
      Map.has_key?(state, key)
    end)
  end

  def lookup(cache_name, key) do
    Agent.get(cache_name, fn state ->
      case Map.get(state, key) do
        nil -> []
        value -> [{key, value}]
      end
    end)
  end

  def lookup_element(cache_name, key, pos) do
    Agent.get(cache_name, fn state ->
      case Map.get(state, key) do
        nil -> raise ArgumentError, "key not found"
        value when is_tuple(value) -> elem(value, pos - 1)
        value -> value
      end
    end)
  end

  def lookup_element(cache_name, key, pos, default) do
    Agent.get(cache_name, fn state ->
      case Map.get(state, key) do
        nil -> default
        value when is_tuple(value) -> elem(value, pos - 1)
        value -> value
      end
    end)
  end

  def update_counter(cache_name, key, {_pos, incr}) do
    Agent.get_and_update(cache_name, fn state ->
      current_value = state[key] || 0
      new_value = current_value + incr
      {new_value, Map.put(state, key, new_value)}
    end)
  end

  def update_counter(cache_name, key, incr) when is_integer(incr) do
    Agent.get_and_update(cache_name, fn state ->
      current_value = state[key] || 0
      new_value = current_value + incr
      {new_value, Map.put(state, key, new_value)}
    end)
  end

  def update_counter(cache_name, key, update_op, default) do
    Agent.get_and_update(cache_name, fn state ->
      if Map.has_key?(state, key) do
        current_value = state[key]
        incr = if is_tuple(update_op), do: elem(update_op, 1), else: update_op
        new_value = current_value + incr
        {new_value, Map.put(state, key, new_value)}
      else
        default_value = if is_tuple(default), do: elem(default, 1), else: default
        incr = if is_tuple(update_op), do: elem(update_op, 1), else: update_op
        new_value = default_value + incr
        {new_value, Map.put(state, key, new_value)}
      end
    end)
  end

  def insert_raw(cache_name, data) when is_tuple(data) do
    key = elem(data, 0)
    value = if tuple_size(data) === 2, do: elem(data, 1), else: data

    Agent.update(cache_name, fn state ->
      Map.put(state, key, value)
    end)

    true
  end

  def insert_raw(cache_name, data) when is_list(data) do
    Agent.update(cache_name, fn state ->
      Enum.reduce(data, state, fn tuple, acc ->
        key = elem(tuple, 0)
        value = if tuple_size(tuple) === 2, do: elem(tuple, 1), else: tuple
        Map.put(acc, key, value)
      end)
    end)

    true
  end

  def insert_new(cache_name, data) when is_tuple(data) do
    key = elem(data, 0)
    value = if tuple_size(data) === 2, do: elem(data, 1), else: data

    Agent.get_and_update(cache_name, fn state ->
      if Map.has_key?(state, key) do
        {false, state}
      else
        {true, Map.put(state, key, value)}
      end
    end)
  end

  def insert_new(cache_name, data) when is_list(data) do
    Agent.get_and_update(cache_name, fn state ->
      keys_exist = Enum.any?(data, fn tuple -> Map.has_key?(state, elem(tuple, 0)) end)

      if keys_exist do
        {false, state}
      else
        new_state =
          Enum.reduce(data, state, fn tuple, acc ->
            key = elem(tuple, 0)
            value = if tuple_size(tuple) === 2, do: elem(tuple, 1), else: tuple
            Map.put(acc, key, value)
          end)

        {true, new_state}
      end
    end)
  end

  def take(cache_name, key) do
    Agent.get_and_update(cache_name, fn state ->
      case Map.pop(state, key) do
        {nil, state} -> {[], state}
        {value, new_state} -> {[{key, value}], new_state}
      end
    end)
  end

  def tab2list(cache_name) do
    Agent.get(cache_name, fn state ->
      Map.to_list(state)
    end)
  end

  def match_object(cache_name, pattern) do
    Agent.get(cache_name, fn state ->
      state
      |> Map.to_list()
      |> Enum.filter(fn {key, value} ->
        match_pattern?({key, value}, pattern)
      end)
    end)
  end

  def match_object(cache_name, pattern, limit) do
    Agent.get(cache_name, fn state ->
      results =
        state
        |> Map.to_list()
        |> Enum.filter(fn {key, value} ->
          match_pattern?({key, value}, pattern)
        end)
        |> Enum.take(limit)

      {results, :end_of_table}
    end)
  end

  def match_pattern(cache_name, pattern) do
    Agent.get(cache_name, fn state ->
      state
      |> Map.to_list()
      |> Enum.filter(fn {key, value} ->
        match_pattern?({key, value}, pattern)
      end)
      |> Enum.map(fn obj -> extract_bindings(obj, pattern) end)
    end)
  end

  def match_pattern(cache_name, pattern, limit) do
    Agent.get(cache_name, fn state ->
      results =
        state
        |> Map.to_list()
        |> Enum.filter(fn {key, value} ->
          match_pattern?({key, value}, pattern)
        end)
        |> Enum.take(limit)
        |> Enum.map(fn obj -> extract_bindings(obj, pattern) end)

      {results, :end_of_table}
    end)
  end

  defp match_pattern?(_object, :_), do: true

  defp match_pattern?(object, pattern) when is_tuple(pattern) and is_tuple(object) do
    if tuple_size(object) === tuple_size(pattern) do
      object_list = Tuple.to_list(object)
      pattern_list = Tuple.to_list(pattern)

      object_list
      |> Enum.zip(pattern_list)
      |> Enum.all?(fn {obj_elem, pat_elem} ->
        match_element?(obj_elem, pat_elem)
      end)
    else
      false
    end
  end

  defp match_pattern?(object, pattern), do: match_element?(object, pattern)

  defp match_element?(_obj, :_), do: true
  defp match_element?(_obj, pattern) when is_atom(pattern) and pattern !== :_, do: binding?(pattern) or false
  defp match_element?(obj, pattern), do: obj === pattern

  defp binding?(atom) when is_atom(atom) do
    atom_str = Atom.to_string(atom)
    String.starts_with?(atom_str, "$")
  end

  defp binding?(_), do: false

  defp extract_bindings(object, pattern) when is_tuple(pattern) and is_tuple(object) do
    object_list = Tuple.to_list(object)
    pattern_list = Tuple.to_list(pattern)

    object_list
    |> Enum.zip(pattern_list)
    |> Enum.filter(fn {_obj_elem, pat_elem} -> binding?(pat_elem) end)
    |> Enum.map(fn {obj_elem, _pat_elem} -> obj_elem end)
  end

  defp extract_bindings(_object, _pattern), do: []

  def select(cache_name, match_spec) do
    Agent.get(cache_name, fn state ->
      state
      |> Map.to_list()
      |> Enum.flat_map(fn {key, value} ->
        apply_match_spec({key, value}, match_spec)
      end)
    end)
  end

  def select(cache_name, match_spec, limit) do
    Agent.get(cache_name, fn state ->
      results =
        state
        |> Map.to_list()
        |> Enum.flat_map(fn {key, value} ->
          apply_match_spec({key, value}, match_spec)
        end)
        |> Enum.take(limit)

      {results, :end_of_table}
    end)
  end

  defp apply_match_spec(object, match_spec) when is_list(match_spec) do
    Enum.flat_map(match_spec, fn spec ->
      apply_single_match_spec(object, spec)
    end)
  end

  defp apply_single_match_spec(object, {pattern, _guards, result_spec}) do
    if match_pattern?(object, pattern) do
      [transform_result(object, result_spec)]
    else
      []
    end
  end

  defp apply_single_match_spec(_object, _spec), do: []

  defp transform_result(object, [:"$_"]), do: object
  defp transform_result({key, _value}, [:"$$"]), do: [key]
  defp transform_result(_object, [result]) when is_atom(result), do: result
  defp transform_result(_object, result), do: result

  def select_count(cache_name, match_spec) do
    Agent.get(cache_name, fn state ->
      state
      |> Map.to_list()
      |> Enum.count(fn {key, value} ->
        result = apply_match_spec({key, value}, match_spec)
        result !== [] and hd(result) === true
      end)
    end)
  end

  def select_delete(cache_name, match_spec) do
    Agent.get_and_update(cache_name, fn state ->
      {to_delete, to_keep} =
        state
        |> Map.to_list()
        |> Enum.split_with(fn {key, value} ->
          result = apply_match_spec({key, value}, match_spec)
          result !== [] and hd(result) === true
        end)

      {length(to_delete), Map.new(to_keep)}
    end)
  end

  def select_replace(cache_name, match_spec) do
    Agent.get_and_update(cache_name, fn state ->
      {count, new_state} =
        state
        |> Map.to_list()
        |> Enum.reduce({0, state}, fn {key, value}, {cnt, acc} ->
          result = apply_match_spec({key, value}, match_spec)

          case result do
            [new_obj] when is_tuple(new_obj) ->
              new_key = elem(new_obj, 0)
              new_value = if tuple_size(new_obj) === 2, do: elem(new_obj, 1), else: new_obj
              {cnt + 1, acc |> Map.delete(key) |> Map.put(new_key, new_value)}

            _ ->
              {cnt, acc}
          end
        end)

      {count, new_state}
    end)
  end

  def match_delete(cache_name, pattern) do
    Agent.update(cache_name, fn state ->
      state
      |> Map.to_list()
      |> Enum.reject(fn {key, value} ->
        match_pattern?({key, value}, pattern)
      end)
      |> Map.new()
    end)

    true
  end

  def info(cache_name) do
    Agent.get(cache_name, fn state ->
      [
        size: map_size(state),
        type: :set,
        named_table: true,
        keypos: 1,
        protection: :public
      ]
    end)
  end

  def info(cache_name, item) do
    info = info(cache_name)
    Keyword.get(info, item)
  end

  def slot(cache_name, i) do
    Agent.get(cache_name, fn state ->
      list = Map.to_list(state)

      if i >= length(list) do
        :"$end_of_table"
      else
        [Enum.at(list, i)]
      end
    end)
  end

  def safe_fixtable(_cache_name, _fix) do
    true
  end

  def init_table(cache_name, init_fun) do
    Agent.update(cache_name, fn _state ->
      read_init_fun(init_fun, %{})
    end)

    true
  end

  defp read_init_fun(init_fun, acc) do
    case init_fun.(:read) do
      :end_of_input ->
        acc

      objects when is_list(objects) ->
        new_acc =
          Enum.reduce(objects, acc, fn tuple, inner_acc ->
            key = elem(tuple, 0)
            value = if tuple_size(tuple) === 2, do: elem(tuple, 1), else: tuple
            Map.put(inner_acc, key, value)
          end)

        read_init_fun(init_fun, new_acc)

      object when is_tuple(object) ->
        key = elem(object, 0)
        value = if tuple_size(object) === 2, do: elem(object, 1), else: object
        read_init_fun(init_fun, Map.put(acc, key, value))
    end
  end

  def to_dets(_cache_name, _dets_table) do
    {:error, :not_supported_in_sandbox}
  end

  def from_dets(_cache_name, _dets_table) do
    {:error, :not_supported_in_sandbox}
  end

  def to_ets(_cache_name) do
    {:error, :not_supported_in_sandbox}
  end

  def to_ets(_cache_name, _ets_table) do
    {:error, :not_supported_in_sandbox}
  end

  def from_ets(_cache_name, _ets_table) do
    {:error, :not_supported_in_sandbox}
  end

  def close(_cache_name) do
    :ok
  end

  def sync(_cache_name) do
    :ok
  end

  def traverse(cache_name, fun) do
    Agent.get_and_update(cache_name, fn state ->
      {results, new_state} =
        state
        |> Map.to_list()
        |> Enum.reduce({[], state}, fn {key, value}, {acc, current_state} ->
          case fun.({key, value}) do
            :continue ->
              {acc, current_state}

            {:continue, result} ->
              {[result | acc], current_state}

            {:done, result} ->
              {[result | acc], current_state}

            :done ->
              {acc, current_state}
          end
        end)

      {Enum.reverse(results), new_state}
    end)
  end

  def bchunk(_cache_name, _continuation) do
    {:error, :not_supported_in_sandbox}
  end

  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_compatible_bchunk_format(_cache_name, _bchunk_format) do
    false
  end

  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_dets_file(_filename) do
    false
  end

  def open_file(_filename) do
    {:error, :not_supported_in_sandbox}
  end

  def open_file(_name, _args) do
    {:error, :not_supported_in_sandbox}
  end

  def pid2name(_pid) do
    :undefined
  end

  def repair_continuation(continuation, _match_spec) do
    continuation
  end

  def file2tab(_filename) do
    {:error, :not_supported_in_sandbox}
  end

  def file2tab(_filename, _options) do
    {:error, :not_supported_in_sandbox}
  end

  def tab2file(_cache_name, _filename) do
    {:error, :not_supported_in_sandbox}
  end

  def tab2file(_cache_name, _filename, _options) do
    {:error, :not_supported_in_sandbox}
  end

  def tabfile_info(_filename) do
    {:error, :not_supported_in_sandbox}
  end

  def table(_cache_name) do
    {:error, :not_supported_in_sandbox}
  end

  def table(_cache_name, _options) do
    {:error, :not_supported_in_sandbox}
  end

  def give_away(_cache_name, _pid, _gift_data) do
    {:error, :not_supported_in_sandbox}
  end

  def rename(_cache_name, _name) do
    {:error, :not_supported_in_sandbox}
  end

  def setopts(_cache_name, _opts) do
    {:error, :not_supported_in_sandbox}
  end

  def whereis(_cache_name) do
    :undefined
  end

  def test_ms(tuple, match_spec) do
    :ets.test_ms(tuple, match_spec)
  end

  def match_spec_compile(match_spec) do
    :ets.match_spec_compile(match_spec)
  end

  def match_spec_run(list, compiled_match_spec) do
    :ets.match_spec_run(list, compiled_match_spec)
  end

  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_compiled_ms(term) do
    :ets.is_compiled_ms(term)
  end

  def update_element(cache_name, key, element_spec) do
    Agent.get_and_update(cache_name, fn state ->
      case Map.get(state, key) do
        nil ->
          {false, state}

        value when is_tuple(value) ->
          new_value = apply_element_spec(value, element_spec)
          {true, Map.put(state, key, new_value)}

        _ ->
          {false, state}
      end
    end)
  end

  def update_element(cache_name, key, element_spec, default) do
    Agent.get_and_update(cache_name, fn state ->
      case Map.get(state, key) do
        nil ->
          {true, Map.put(state, key, default)}

        value when is_tuple(value) ->
          new_value = apply_element_spec(value, element_spec)
          {true, Map.put(state, key, new_value)}

        _ ->
          {false, state}
      end
    end)
  end

  defp apply_element_spec(tuple, {pos, value}) do
    put_elem(tuple, pos - 1, value)
  end

  defp apply_element_spec(tuple, specs) when is_list(specs) do
    Enum.reduce(specs, tuple, fn {pos, value}, acc ->
      put_elem(acc, pos - 1, value)
    end)
  end

  def select_reverse(cache_name, match_spec) do
    result = select(cache_name, match_spec)
    Enum.reverse(result)
  end

  def select_reverse(cache_name, match_spec, limit) do
    {results, continuation} = select(cache_name, match_spec, limit)
    {Enum.reverse(results), continuation}
  end

  def smembers(_cache_name, _key, _opts) do
    raise "Not Implemented"
  end

  def sadd(_cache_name, _key, _value, _opts) do
    raise "Not Implemented"
  end

  defp put_hash_field_values(state, key, fields_values) do
    Map.update(
      state,
      key,
      Map.new(fields_values),
      &Enum.reduce(fields_values, &1, fn {field, value}, acc -> Map.put(acc, field, value) end)
    )
  end

  defp check_key_exists(state, key) do
    if Map.has_key?(state, key) do
      :ok
    else
      {:error, ErrorMessage.bad_request("ERR new objects must be created at the root")}
    end
  end

  defp check_path_exists(state, key, path) do
    case get_in(state, [key | String.split(path, ".")]) do
      nil -> {:ok, nil}
      _ -> :ok
    end
  end

  defp add_defaults([key | keys]) do
    [Access.key(key, key_default(key)) | add_defaults(keys)]
  end

  defp add_defaults(keys), do: keys

  defp key_default(key) do
    if Regex.match?(~r/\d+/, key), do: [], else: %{}
  end

  defp stringify_value(value) do
    value
    |> TermEncoder.encode_json()
    |> TermEncoder.decode_json()
  end

  defp contains_index?(path) do
    path
    |> List.last()
    |> is_integer()
  end

  defp serialize_path_and_get_value(cache_name, key, path) do
    path = JSON.serialize_path(path)

    Agent.get(cache_name, fn state ->
      case get_in(state, [key | String.split(path, ".")]) do
        nil -> {:error, ErrorMessage.not_found("ERR Path '$.#{path}' does not exist")}
        value -> {:ok, value}
      end
    end)
  end

  defp enum_length(m) when is_map(m), do: m |> Map.to_list() |> enum_length()
  defp enum_length(l), do: length(l)
end
