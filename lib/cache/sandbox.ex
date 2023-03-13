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

  def hash_values(cache_name, key, _opts) do
    Agent.get(cache_name, fn state ->
      {:ok, Map.values(state[key] || %{})}
    end)
  end

  def hash_set(cache_name, key, hash_key, value, _opts) do
    Agent.update(cache_name, fn state ->
      Map.update(state, key, %{hash_key => value}, &Map.put(&1, hash_key, value))
    end)
  end

  def hash_set_many(cache_name, keys_fields_values, _ttl \\ nil, _opts) do
    Agent.update(cache_name, fn state ->
      Enum.reduce(keys_fields_values, state, fn {key, field_values}, state ->
        Map.put(state, key, Map.new(field_values))
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
end
