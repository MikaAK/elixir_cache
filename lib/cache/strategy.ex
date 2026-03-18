defmodule Cache.Strategy do
  @moduledoc """
  Behaviour for strategy-based cache adapters.

  Strategy adapters compose over existing cache adapters to provide higher-level
  caching patterns such as consistent hashing, multi-layer cascading, and
  refresh-ahead semantics.

  Unlike regular adapters which implement `Cache` directly, strategy adapters
  receive the underlying adapter module and its resolved options so they can
  delegate operations appropriately.

  ## Usage

  Strategies are specified using the tuple format in `use Cache`:

  ```elixir
  use Cache,
    adapter: {Cache.HashRing, Cache.ETS},
    name: :my_cache,
    opts: [read_concurrency: true]
  ```

  The first element is the strategy module, the second is the underlying adapter
  (or strategy-specific configuration).
  """

  @doc """
  Returns the NimbleOptions schema for validating strategy-level opts.
  """
  @callback opts_definition() :: Keyword.t()

  @doc """
  Returns a supervisor child spec for the strategy.

  Receives the cache name, strategy config (the second element of the adapter
  tuple), and the resolved underlying adapter opts.
  """
  @callback child_spec({
              cache_name :: atom,
              strategy_config :: term,
              adapter_opts :: Keyword.t()
            }) :: Supervisor.child_spec() | :supervisor.child_spec()

  @doc """
  Fetches a value from the cache using the strategy's routing/layering logic.
  """
  @callback get(
              cache_name :: atom,
              key :: atom | String.t(),
              strategy_config :: term,
              adapter_opts :: Keyword.t()
            ) :: ErrorMessage.t_res(any)

  @doc """
  Stores a value in the cache using the strategy's routing/layering logic.
  """
  @callback put(
              cache_name :: atom,
              key :: atom | String.t(),
              ttl :: pos_integer | nil,
              value :: any,
              strategy_config :: term,
              adapter_opts :: Keyword.t()
            ) :: :ok | ErrorMessage.t()

  @doc """
  Removes a value from the cache using the strategy's routing/layering logic.
  """
  @callback delete(
              cache_name :: atom,
              key :: atom | String.t(),
              strategy_config :: term,
              adapter_opts :: Keyword.t()
            ) :: :ok | ErrorMessage.t()

  @doc """
  Returns true if the given module implements the `Cache.Strategy` behaviour.
  """
  @spec strategy?(module()) :: boolean()
  def strategy?(module) do
    module
    |> module_behaviours()
    |> Enum.member?(Cache.Strategy)
  rescue
    _ -> false
  end

  defp module_behaviours(module) do
    module
    |> :erlang.apply(:module_info, [:attributes])
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  rescue
    _ -> []
  end
end
