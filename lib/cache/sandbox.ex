defmodule Cache.Sandbox do
  @moduledoc """
  This module is the adapter used by the SandboxRegistry to mock out all the other adapters
  therefore it must implement all features shared across all adapters. It uses a basic `Agent`
  and shouldn't be used in production. It's good for dev & test to avoid needing dependencies
  """

  use Agent

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
      {:ok, state[key]}
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
        Enum.map(keys_fields_values, fn {_, fields_values} -> length(fields_values) end)

      expiry_resps = Enum.map(keys_fields_values, fn _ -> 1 end)
      {:ok, command_resps ++ expiry_resps}
    else
      :ok
    end
  end

  defp put_hash_field_values(state, key, fields_values) do
    Map.update(
      state,
      key,
      Map.new(fields_values),
      &Enum.reduce(fields_values, &1, fn {field, value}, acc -> Map.put(acc, field, value) end)
    )
  end

  def json_get(cache_name, key, path, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(state, key, nil, &get_in(&1, String.split(path, ".")))
    end)
  end

  def json_set(cache_name, key, path, value, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(state, key, nil, &put_in(&1, String.split(path, "."), value))
    end)
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
      Map.update(state, key, nil, &update_in(&1, String.split(path, "."), fn
        integer when is_integer(integer) -> 0
        list when is_list(list) -> []
        map when is_map(map) -> %{}
        _ -> nil
      end))
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

  def scan(_cache_name, _scan_opts, _opts) do
    raise "Not Implemented"
  end

  def hash_scan(_cache_name, _key, _scan_opts, _opts) do
    raise "Not Implemented"
  end
end
