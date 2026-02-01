defmodule Cache.Agent do
  @moduledoc """
  Agent-based adapter for lightweight in-memory caching.

  This adapter uses Elixir's built-in `Agent` for simple key-value storage.
  It's ideal for development, testing, or applications with minimal caching needs.

  ## Features

  * Simple in-memory storage using Elixir Agents
  * No external dependencies
  * Lightweight and easy to set up
  * No TTL support (values persist until deleted or process terminates)

  ## Example

      defmodule MyApp.SimpleCache do
        use Cache,
          adapter: Cache.Agent,
          name: :simple_cache,
          opts: []
      end

  ## Usage

      iex> {:ok, _pid} = Cache.Agent.start_link(name: :test_agent_cache)
      iex> Cache.Agent.put(:test_agent_cache, "key", nil, "value")
      :ok
      iex> Cache.Agent.get(:test_agent_cache, "key")
      {:ok, "value"}
      iex> Cache.Agent.delete(:test_agent_cache, "key")
      :ok
      iex> Cache.Agent.get(:test_agent_cache, "key")
      {:ok, nil}
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
      start: {Cache.Agent, :start_link, [Keyword.put(opts, :name, cache_name)]}
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
end
