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

  ```elixir
  defmodule MyApp.TestCache do
    use Cache,
      adapter: Cache.Redis,  # Original adapter doesn't matter when sandbox is enabled
      name: :test_cache,
      opts: [],
      sandbox?: Mix.env() == :test
  end
  ```

  In your tests, use `Cache.SandboxRegistry.start(MyApp.TestCache)` in the setup block to ensure
  proper isolation between test cases.

  > **Note**: This adapter should not be used in production environments.

  ## Isolation

  Each Agent process keeps state shaped as `%{sandbox_id => %{key => value}}`. The
  `sandbox_id` is resolved per-caller via `Cache.SandboxRegistry` BEFORE entering
  the Agent callback (so the caller's `self()`/`$callers`/`$ancestors` are used
  for lookup, not the Agent's). When no sandbox is registered for the caller we
  fall back to `:__unscoped__` — keeping the adapter usable outside of test.
  """

  use Agent

  alias Cache.Redis.JSON
  alias Cache.TermEncoder

  @behaviour Cache

  @sandbox_registry :elixir_cache_sandbox
  @unscoped :__unscoped__

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

  # SECTION: sandbox scoping helpers

  # Resolve the sandbox id for the current caller. Must be called from the
  # caller process (NOT inside the Agent callback) so SandboxRegistry can walk
  # the caller's $callers/$ancestors.
  defp current_sandbox_id(cache_name) do
    case Process.whereis(@sandbox_registry) do
      nil ->
        @unscoped

      _pid ->
        case SandboxRegistry.lookup(@sandbox_registry, cache_name) do
          {:ok, id} -> id
          {:error, _} -> @unscoped
        end
    end
  end

  defp scoped_get(state, sid), do: Map.get(state, sid, %{})
  defp scoped_put(state, sid, sub), do: Map.put(state, sid, sub)

  defp scoped_agent_get(cache_name, fun) do
    sid = current_sandbox_id(cache_name)
    Agent.get(cache_name, fn state -> fun.(scoped_get(state, sid)) end)
  end

  defp scoped_agent_update(cache_name, fun) do
    sid = current_sandbox_id(cache_name)
    Agent.update(cache_name, fn state -> scoped_put(state, sid, fun.(scoped_get(state, sid))) end)
  end

  defp scoped_agent_get_and_update(cache_name, fun) do
    sid = current_sandbox_id(cache_name)

    Agent.get_and_update(cache_name, fn state ->
      {reply, new_sub} = fun.(scoped_get(state, sid))
      {reply, scoped_put(state, sid, new_sub)}
    end)
  end

  # SECTION: core cache API

  @impl Cache
  def get(cache_name, key, _opts \\ []) do
    scoped_agent_get(cache_name, fn sub -> {:ok, Map.get(sub, key)} end)
  end

  @impl Cache
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ []) do
    scoped_agent_update(cache_name, fn sub -> Map.put(sub, key, value) end)
  end

  @impl Cache
  def delete(cache_name, key, _opts \\ []) do
    scoped_agent_update(cache_name, fn sub -> Map.delete(sub, key) end)
  end

  def get_or_store(cache_name, key, _ttl, store_fun) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      case Map.fetch(sub, key) do
        {:ok, value} ->
          {value, sub}

        :error ->
          value = store_fun.()
          {value, Map.put(sub, key, value)}
      end
    end)
  end

  def dirty_get_or_store(cache_name, key, store_fun) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      case Map.fetch(sub, key) do
        {:ok, value} ->
          {value, sub}

        :error ->
          value = store_fun.()
          {value, Map.put(sub, key, value)}
      end
    end)
  end

  # SECTION: hash API

  def hash_delete(cache_name, key, hash_key, _opts) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      case Map.get(sub, key) do
        nil ->
          {{:ok, 0}, sub}

        value when is_map(value) ->
          if Map.has_key?(value, hash_key) do
            updated = Map.delete(value, hash_key)

            new_sub =
              if Enum.empty?(updated) do
                Map.delete(sub, key)
              else
                Map.put(sub, key, updated)
              end

            {{:ok, 1}, new_sub}
          else
            {{:ok, 0}, sub}
          end

        _ ->
          {{:ok, 0}, sub}
      end
    end)
  end

  def hash_get(cache_name, key, hash_key, _opts) do
    scoped_agent_get(cache_name, fn sub ->
      value =
        sub
        |> Map.get(key, %{})
        |> Map.get(hash_key)

      {:ok, value}
    end)
  end

  def hash_get_all(cache_name, key, _opts) do
    scoped_agent_get(cache_name, fn sub ->
      case sub[key] do
        nil -> {:ok, %{}}
        value -> {:ok, value}
      end
    end)
  end

  def hash_get_many(cache_name, keys_fields, _opts) do
    scoped_agent_get(cache_name, fn sub ->
      values =
        Enum.map(keys_fields, fn {key, fields} ->
          hash = Map.get(sub, key, %{})
          Enum.map(fields, &Map.get(hash, &1))
        end)

      {:ok, values}
    end)
  end

  def hash_values(cache_name, key, _opts) do
    scoped_agent_get(cache_name, fn sub ->
      {:ok, Map.values(sub[key] || %{})}
    end)
  end

  def hash_set(cache_name, key, field, value, ttl, _opts) do
    count =
      scoped_agent_get_and_update(cache_name, fn sub ->
        hash = Map.get(sub, key, %{})
        is_new_field = not Map.has_key?(hash, field)
        updated_hash = Map.put(hash, field, value)

        {if(is_new_field, do: 1, else: 0), Map.put(sub, key, updated_hash)}
      end)

    if ttl do
      {:ok, [count, 1]}
    else
      {:ok, count}
    end
  end

  def hash_set_many(cache_name, keys_fields_values, ttl, _opts) do
    counts =
      scoped_agent_get_and_update(cache_name, fn sub ->
        {counts, new_sub} =
          Enum.map_reduce(keys_fields_values, sub, fn {key, fields_values}, acc ->
            hash = Map.get(acc, key, %{})

            {updated_hash, count} =
              Enum.reduce(fields_values, {hash, 0}, fn {field, value}, {hash_acc, count_acc} ->
                is_new_field = not Map.has_key?(hash_acc, field)
                updated_hash = Map.put(hash_acc, field, value)
                new_count = if is_new_field, do: count_acc + 1, else: count_acc

                {updated_hash, new_count}
              end)

            {count, Map.put(acc, key, updated_hash)}
          end)

        {counts, new_sub}
      end)

    if ttl do
      expiry_resps = List.duplicate(1, enum_length(keys_fields_values))
      {:ok, counts ++ expiry_resps}
    else
      {:ok, counts}
    end
  end

  # SECTION: JSON API

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
    sub = scoped_agent_get(cache_name, & &1)
    path = JSON.serialize_path(path)

    with :ok <- check_key_exists(sub, key),
         :ok <- check_path_exists(sub, key, path) do
      path = add_defaults([key | String.split(path, ".")])
      value = stringify_value(value)

      scoped_agent_update(cache_name, fn sub ->
        put_in(sub, path, value)
      end)
    end
  end

  def json_incr(cache_name, key, path, incr \\ 1, _opts) do
    path_parts = json_path_parts(path)
    path_string = json_path_string(path)

    scoped_agent_get_and_update(cache_name, fn sub ->
      case get_in(sub, [key | path_parts]) do
        nil ->
          {{:error, ErrorMessage.not_found("ERR Path '$.#{path_string}' does not exist")}, sub}

        value ->
          new_value = value + incr
          {{:ok, new_value}, put_in(sub, [key | path_parts], new_value)}
      end
    end)
  end

  def json_clear(cache_name, key, path, _opts) do
    path_parts = json_path_parts(path)

    scoped_agent_get_and_update(cache_name, fn sub ->
      case get_in(sub, [key | path_parts]) do
        nil ->
          {{:ok, 0}, sub}

        value ->
          updated_value =
            case value do
              integer when is_integer(integer) -> 0
              list when is_list(list) -> []
              map when is_map(map) -> %{}
              _ -> nil
            end

          {{:ok, 1}, put_in(sub, [key | path_parts], updated_value)}
      end
    end)
  end

  def json_delete(cache_name, key, path, _opts) do
    path_parts = json_path_parts(path)

    scoped_agent_get_and_update(cache_name, fn sub ->
      case get_in(sub, [key | path_parts]) do
        nil ->
          {{:ok, 0}, sub}

        _value ->
          {_, updated} = pop_in(sub, [key | path_parts])
          {{:ok, 1}, updated}
      end
    end)
  end

  def json_array_append(cache_name, key, path, values, _opts) when is_list(values) do
    append_json_array(cache_name, key, path, values, &stringify_value/1)
  end

  def json_array_append(cache_name, key, path, value, _opts) do
    append_json_array(cache_name, key, path, [value], &stringify_value/1)
  end

  defp append_json_array(cache_name, key, path, values, value_transformer) do
    path_parts = json_path_parts(path)
    path_string = json_path_string(path)
    updated_values = Enum.map(values, value_transformer)

    scoped_agent_get_and_update(cache_name, fn sub ->
      case get_in(sub, [key | path_parts]) do
        nil ->
          {{:error, ErrorMessage.not_found("ERR Path '$.#{path_string}' does not exist")}, sub}

        list when is_list(list) ->
          updated_list = list ++ updated_values
          new_sub = put_in(sub, [key | path_parts], updated_list)
          {{:ok, enum_length(updated_list)}, new_sub}

        _ ->
          {{:error, ErrorMessage.not_found("ERR Path '$.#{path_string}' does not exist")}, sub}
      end
    end)
  end

  # SECTION: Redis compatibility

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

  def scan(cache_name, scan_opts, _opts) do
    match = scan_opts[:match] || "*"
    count = scan_opts[:count]
    type = scan_opts[:type]

    scoped_agent_get(cache_name, fn sub ->
      values =
        sub
        |> Stream.filter(fn {_key, value} -> scan_type_match?(value, type) end)
        |> Stream.map(fn {key, _value} -> key end)
        |> Stream.filter(fn key -> scan_match?(key, match) end)
        |> Enum.to_list()
        |> apply_scan_count(count)

      {:ok, values}
    end)
  end

  def hash_scan(cache_name, key, scan_opts, _opts) do
    match = scan_opts[:match] || "*"
    count = scan_opts[:count]

    scoped_agent_get(cache_name, fn sub ->
      case Map.get(sub, key) do
        map when is_map(map) ->
          elements =
            map
            |> Enum.filter(fn {field, _value} -> scan_match?(field, match) end)
            |> apply_scan_count(count)

          {:ok, elements}

        _ ->
          {:ok, []}
      end
    end)
  end

  # SECTION: ETS & DETS compatibility
  #
  # All ETS/DETS-style helpers below operate on the scoped sub-map for the
  # current sandbox so tests stay isolated from each other.

  def all do
    sid = current_sandbox_id(Cache.Sandbox)

    Agent.get(Cache.Sandbox, fn state -> state |> scoped_get(sid) |> Map.keys() end)
  rescue
    _ -> []
  end

  def delete_table(cache_name) do
    scoped_agent_update(cache_name, fn _ -> %{} end)
    true
  end

  def delete_all_objects(cache_name) do
    scoped_agent_update(cache_name, fn _ -> %{} end)
    true
  end

  def delete_object(cache_name, object) when is_tuple(object) do
    key = elem(object, 0)

    scoped_agent_update(cache_name, fn sub ->
      case Map.get(sub, key) do
        ^object -> Map.delete(sub, key)
        _ -> sub
      end
    end)

    true
  end

  def first(cache_name) do
    scoped_agent_get(cache_name, fn sub ->
      case Map.keys(sub) do
        [] -> :"$end_of_table"
        [key | _] -> key
      end
    end)
  end

  def first_lookup(cache_name) do
    scoped_agent_get(cache_name, fn sub ->
      case Map.to_list(sub) do
        [] -> :"$end_of_table"
        [{key, value} | _] -> {key, [{key, value}]}
      end
    end)
  end

  def last(cache_name) do
    scoped_agent_get(cache_name, fn sub ->
      case sub |> Map.keys() |> Enum.reverse() do
        [] -> :"$end_of_table"
        [key | _] -> key
      end
    end)
  end

  def last_lookup(cache_name) do
    scoped_agent_get(cache_name, fn sub ->
      case sub |> Map.to_list() |> Enum.reverse() do
        [] -> :"$end_of_table"
        [{key, value} | _] -> {key, [{key, value}]}
      end
    end)
  end

  def next(cache_name, key) do
    scoped_agent_get(cache_name, fn sub ->
      keys = sub |> Map.keys() |> Enum.sort()
      find_next_key(keys, key)
    end)
  end

  def next_lookup(cache_name, key) do
    scoped_agent_get(cache_name, fn sub ->
      keys = sub |> Map.keys() |> Enum.sort()

      case find_next_key(keys, key) do
        :"$end_of_table" -> :"$end_of_table"
        next_key -> {next_key, [{next_key, Map.get(sub, next_key)}]}
      end
    end)
  end

  def prev(cache_name, key) do
    scoped_agent_get(cache_name, fn sub ->
      keys = sub |> Map.keys() |> Enum.sort() |> Enum.reverse()
      find_next_key(keys, key)
    end)
  end

  def prev_lookup(cache_name, key) do
    scoped_agent_get(cache_name, fn sub ->
      keys = sub |> Map.keys() |> Enum.sort() |> Enum.reverse()

      case find_next_key(keys, key) do
        :"$end_of_table" -> :"$end_of_table"
        prev_key -> {prev_key, [{prev_key, Map.get(sub, prev_key)}]}
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
    scoped_agent_get(cache_name, fn sub ->
      sub
      |> Map.to_list()
      |> Enum.reduce(acc, fn {key, value}, acc_inner ->
        function.({key, value}, acc_inner)
      end)
    end)
  end

  def foldr(cache_name, function, acc) do
    scoped_agent_get(cache_name, fn sub ->
      sub
      |> Map.to_list()
      |> Enum.reverse()
      |> Enum.reduce(acc, fn {key, value}, acc_inner ->
        function.({key, value}, acc_inner)
      end)
    end)
  end

  def member(cache_name, key) do
    scoped_agent_get(cache_name, fn sub -> Map.has_key?(sub, key) end)
  end

  def lookup(cache_name, key) do
    scoped_agent_get(cache_name, fn sub ->
      case Map.get(sub, key) do
        nil -> []
        value -> [{key, value}]
      end
    end)
  end

  def lookup_element(cache_name, key, pos) do
    scoped_agent_get(cache_name, fn sub ->
      case Map.get(sub, key) do
        nil -> raise ArgumentError, "key not found"
        value when is_tuple(value) -> elem(value, pos - 1)
        value -> value
      end
    end)
  end

  def lookup_element(cache_name, key, pos, default) do
    scoped_agent_get(cache_name, fn sub ->
      case Map.get(sub, key) do
        nil -> default
        value when is_tuple(value) -> elem(value, pos - 1)
        value -> value
      end
    end)
  end

  def update_counter(cache_name, key, {_pos, incr}) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      current_value = sub[key] || 0
      new_value = current_value + incr
      {new_value, Map.put(sub, key, new_value)}
    end)
  end

  def update_counter(cache_name, key, incr) when is_integer(incr) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      current_value = sub[key] || 0
      new_value = current_value + incr
      {new_value, Map.put(sub, key, new_value)}
    end)
  end

  def update_counter(cache_name, key, update_op, default) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      if Map.has_key?(sub, key) do
        current_value = sub[key]
        incr = if is_tuple(update_op), do: elem(update_op, 1), else: update_op
        new_value = current_value + incr
        {new_value, Map.put(sub, key, new_value)}
      else
        default_value = if is_tuple(default), do: elem(default, 1), else: default
        incr = if is_tuple(update_op), do: elem(update_op, 1), else: update_op
        new_value = default_value + incr
        {new_value, Map.put(sub, key, new_value)}
      end
    end)
  end

  def insert_raw(cache_name, data) when is_tuple(data) do
    key = elem(data, 0)
    value = if tuple_size(data) === 2, do: elem(data, 1), else: data

    scoped_agent_update(cache_name, fn sub -> Map.put(sub, key, value) end)
    true
  end

  def insert_raw(cache_name, data) when is_list(data) do
    scoped_agent_update(cache_name, fn sub ->
      Enum.reduce(data, sub, fn tuple, acc ->
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

    scoped_agent_get_and_update(cache_name, fn sub ->
      if Map.has_key?(sub, key) do
        {false, sub}
      else
        {true, Map.put(sub, key, value)}
      end
    end)
  end

  def insert_new(cache_name, data) when is_list(data) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      keys_exist = Enum.any?(data, fn tuple -> Map.has_key?(sub, elem(tuple, 0)) end)

      if keys_exist do
        {false, sub}
      else
        new_sub =
          Enum.reduce(data, sub, fn tuple, acc ->
            key = elem(tuple, 0)
            value = if tuple_size(tuple) === 2, do: elem(tuple, 1), else: tuple
            Map.put(acc, key, value)
          end)

        {true, new_sub}
      end
    end)
  end

  def take(cache_name, key) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      case Map.pop(sub, key) do
        {nil, sub} -> {[], sub}
        {value, new_sub} -> {[{key, value}], new_sub}
      end
    end)
  end

  def tab2list(cache_name) do
    scoped_agent_get(cache_name, fn sub -> Map.to_list(sub) end)
  end

  def match_object(cache_name, pattern) do
    scoped_agent_get(cache_name, fn sub ->
      sub
      |> Map.to_list()
      |> Enum.filter(fn {key, value} -> match_pattern?({key, value}, pattern) end)
    end)
  end

  def match_object(cache_name, pattern, limit) do
    scoped_agent_get(cache_name, fn sub ->
      results =
        sub
        |> Map.to_list()
        |> Enum.filter(fn {key, value} -> match_pattern?({key, value}, pattern) end)
        |> Enum.take(limit)

      {results, :end_of_table}
    end)
  end

  def match_pattern(cache_name, pattern) do
    scoped_agent_get(cache_name, fn sub ->
      sub
      |> Map.to_list()
      |> Enum.filter(fn {key, value} -> match_pattern?({key, value}, pattern) end)
      |> Enum.map(fn obj -> extract_bindings(obj, pattern) end)
    end)
  end

  def match_pattern(cache_name, pattern, limit) do
    scoped_agent_get(cache_name, fn sub ->
      results =
        sub
        |> Map.to_list()
        |> Enum.filter(fn {key, value} -> match_pattern?({key, value}, pattern) end)
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
      |> Enum.all?(fn {obj_elem, pat_elem} -> match_element?(obj_elem, pat_elem) end)
    else
      false
    end
  end

  defp match_pattern?(object, pattern), do: match_element?(object, pattern)

  defp match_element?(_obj, :_), do: true

  defp match_element?(obj, pattern) when is_atom(pattern) do
    if binding?(pattern), do: true, else: obj === pattern
  end

  defp match_element?(obj, pattern) when is_tuple(obj) and is_tuple(pattern) do
    match_pattern?(obj, pattern)
  end

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
    scoped_agent_get(cache_name, fn sub ->
      sub
      |> Map.to_list()
      |> Enum.flat_map(fn {key, value} -> apply_match_spec({key, value}, match_spec) end)
    end)
  end

  def select(cache_name, match_spec, limit) do
    scoped_agent_get(cache_name, fn sub ->
      results =
        sub
        |> Map.to_list()
        |> Enum.flat_map(fn {key, value} -> apply_match_spec({key, value}, match_spec) end)
        |> Enum.take(limit)

      {results, :end_of_table}
    end)
  end

  defp apply_match_spec(object, match_spec) when is_list(match_spec) do
    Enum.flat_map(match_spec, fn spec -> apply_single_match_spec(object, spec) end)
  end

  # NOTE: Guards are not evaluated in the sandbox. Implementing a full guard
  # interpreter for match specs is non-trivial and unlikely to be needed in
  # typical test scenarios. If you rely on guards in match specs, consider
  # testing against the real adapter.
  defp apply_single_match_spec(object, {pattern, _guards, result_spec}) do
    if match_pattern?(object, pattern) do
      bindings = extract_numbered_bindings(object, pattern)
      [transform_result(object, result_spec, bindings)]
    else
      []
    end
  end

  defp apply_single_match_spec(_object, _spec), do: []

  defp extract_numbered_bindings(object, pattern)
       when is_tuple(pattern) and is_tuple(object) do
    object_list = Tuple.to_list(object)
    pattern_list = Tuple.to_list(pattern)

    object_list
    |> Enum.zip(pattern_list)
    |> Enum.reduce(%{}, fn {obj_elem, pat_elem}, acc ->
      case parse_binding_number(pat_elem) do
        nil -> acc
        n -> Map.put(acc, n, obj_elem)
      end
    end)
  end

  defp extract_numbered_bindings(_object, _pattern), do: %{}

  defp parse_binding_number(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "$" <> rest ->
        case Integer.parse(rest) do
          {n, ""} -> n
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_binding_number(_), do: nil

  defp transform_result(object, [:"$_"], _bindings), do: object

  defp transform_result(_object, [:"$$"], bindings) do
    bindings
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp transform_result(_object, [result], bindings) do
    resolve_bindings(result, bindings)
  end

  defp transform_result(_object, result, _bindings), do: result

  defp resolve_bindings(atom, bindings) when is_atom(atom) do
    case parse_binding_number(atom) do
      nil -> atom
      n -> Map.get(bindings, n, atom)
    end
  end

  defp resolve_bindings(tuple, bindings) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&resolve_bindings(&1, bindings))
    |> List.to_tuple()
  end

  defp resolve_bindings(list, bindings) when is_list(list) do
    Enum.map(list, &resolve_bindings(&1, bindings))
  end

  defp resolve_bindings(value, _bindings), do: value

  def select_count(cache_name, match_spec) do
    scoped_agent_get(cache_name, fn sub ->
      sub
      |> Map.to_list()
      |> Enum.count(fn {key, value} ->
        result = apply_match_spec({key, value}, match_spec)
        result !== [] and hd(result) === true
      end)
    end)
  end

  def select_delete(cache_name, match_spec) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      {to_delete, to_keep} =
        sub
        |> Map.to_list()
        |> Enum.split_with(fn {key, value} ->
          result = apply_match_spec({key, value}, match_spec)
          result !== [] and hd(result) === true
        end)

      {length(to_delete), Map.new(to_keep)}
    end)
  end

  def select_replace(cache_name, match_spec) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      {count, new_sub} =
        sub
        |> Map.to_list()
        |> Enum.reduce({0, sub}, fn {key, value}, {cnt, acc} ->
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

      {count, new_sub}
    end)
  end

  def match_delete(cache_name, pattern) do
    scoped_agent_update(cache_name, fn sub ->
      sub
      |> Map.to_list()
      |> Enum.reject(fn {key, value} -> match_pattern?({key, value}, pattern) end)
      |> Map.new()
    end)

    true
  end

  def info(cache_name) do
    scoped_agent_get(cache_name, fn sub ->
      [
        name: cache_name,
        size: map_size(sub),
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
    scoped_agent_get(cache_name, fn sub ->
      list = Map.to_list(sub)

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
    scoped_agent_update(cache_name, fn _sub -> read_init_fun(init_fun, %{}) end)
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
    scoped_agent_get_and_update(cache_name, fn sub ->
      {results, new_sub} =
        sub
        |> Map.to_list()
        |> Enum.reduce({[], sub}, fn {key, value}, {acc, current_sub} ->
          case fun.({key, value}) do
            :continue ->
              {acc, current_sub}

            {:continue, result} ->
              {[result | acc], current_sub}

            {:done, result} ->
              {[result | acc], current_sub}

            :done ->
              {acc, current_sub}
          end
        end)

      {Enum.reverse(results), new_sub}
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
    scoped_agent_get_and_update(cache_name, fn sub ->
      case Map.get(sub, key) do
        nil ->
          {false, sub}

        value when is_tuple(value) ->
          new_value = apply_element_spec(value, element_spec)
          {true, Map.put(sub, key, new_value)}

        _ ->
          {false, sub}
      end
    end)
  end

  def update_element(cache_name, key, element_spec, default) do
    scoped_agent_get_and_update(cache_name, fn sub ->
      case Map.get(sub, key) do
        nil ->
          {true, Map.put(sub, key, default)}

        value when is_tuple(value) ->
          new_value = apply_element_spec(value, element_spec)
          {true, Map.put(sub, key, new_value)}

        _ ->
          {false, sub}
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

  # SECTION: internal helpers

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

  defp apply_scan_count(values, nil), do: values
  defp apply_scan_count(values, count) when is_integer(count), do: Enum.take(values, count)

  defp scan_match?(value, pattern) do
    value
    |> to_string()
    |> then(&Regex.match?(scan_pattern_regex(pattern), &1))
  end

  defp scan_type_match?(_value, nil), do: true
  defp scan_type_match?(value, "hash"), do: is_map(value)
  defp scan_type_match?(value, "list"), do: is_list(value)
  defp scan_type_match?(_value, "string"), do: true
  defp scan_type_match?(_value, _type), do: false

  defp scan_pattern_regex(pattern) do
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*")
    |> String.replace("\\?", ".")
    |> then(&("^" <> &1 <> "$"))
    |> Regex.compile!()
  end

  defp json_path_parts(path) when path in [nil, ["."]] do
    []
  end

  defp json_path_parts(path) when is_list(path) do
    path
    |> JSON.serialize_path()
    |> String.split(".")
  end

  defp json_path_parts(path) when is_binary(path) do
    String.split(path, ".")
  end

  defp json_path_string(path) when path in [nil, ["."]] do
    ""
  end

  defp json_path_string(path) when is_list(path) do
    JSON.serialize_path(path)
  end

  defp json_path_string(path) when is_binary(path) do
    path
  end

  defp serialize_path_and_get_value(cache_name, key, path) do
    path = JSON.serialize_path(path)

    scoped_agent_get(cache_name, fn sub ->
      case get_in(sub, [key | String.split(path, ".")]) do
        nil -> {:error, ErrorMessage.not_found("ERR Path '$.#{path}' does not exist")}
        value -> {:ok, value}
      end
    end)
  end

  defp enum_length(m) when is_map(m), do: m |> Map.to_list() |> enum_length()
  defp enum_length(l), do: length(l)
end
