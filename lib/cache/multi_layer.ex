defmodule Cache.MultiLayer do
  @moduledoc """
  Multi-layer caching strategy that cascades through multiple cache layers.

  Keys are read from fastest to slowest, with automatic backfill on cache hits
  from slower layers. Writes go slowest-first to avoid polluting fast layers
  with data that failed to persist in slow ones.

  ## Usage

  Pass a list of layers as the strategy config. Each element can be:

  - A module that implements `Cache` (already running, not supervised by this adapter)
  - An adapter module (e.g. `Cache.ETS`) — will be auto-started and supervised
  - A tuple `{AdapterModule, opts}` — adapter with inline opts

  ```elixir
  defmodule MyApp.LayeredCache do
    use Cache,
      adapter: {Cache.MultiLayer, [Cache.ETS, MyApp.RedisCache]},
      name: :layered_cache,
      opts: []
  end
  ```

  ## `__MODULE__` in Layers

  You may include `__MODULE__` in the layer list to position the current
  module's own underlying cache within the chain. If `__MODULE__` is omitted,
  no local cache is created for the defining module—it acts as a pure facade.

  ```elixir
  defmodule MyApp.LayeredCache do
    use Cache,
      adapter: {Cache.MultiLayer, [Cache.ETS, __MODULE__, MyApp.RedisCache]},
      name: :layered_cache,
      opts: [uri: "redis://localhost"]
  end
  ```

  ## Read Behaviour

  Layers are iterated fastest → slowest (list order). On a hit from layer N,
  the value is backfilled into layers 1..N-1.

  ## Write Behaviour

  Layers are written slowest → fastest (reverse list order). If a slow write
  fails, the write stops and an error is returned — preventing polluting faster
  layers with potentially-unsaved data.

  ## Fetch Callback (Optional)

  If all layers miss, an optional fetch callback can supply the value. The
  fetched value is then backfilled into all layers.

  Define it as a module callback or pass it via opts:

  ```elixir
  defmodule MyApp.LayeredCache do
    use Cache,
      adapter: {Cache.MultiLayer, [Cache.ETS, MyApp.RedisCache]},
      name: :layered_cache,
      opts: [on_fetch: &__MODULE__.fetch/1]

    def fetch(key) do
      {:ok, "value_for_\#{key}"}
    end
  end
  ```

  ## Options

  #{NimbleOptions.docs([
    on_fetch: [
      type: {:or, [:mfa, {:fun, 1}]},
      doc: "Optional fetch callback invoked on total cache miss. Receives the key, returns `{:ok, value}` or `{:error, reason}`."
    ],
    backfill_ttl: [
      type: {:or, [:pos_integer, nil]},
      doc: "TTL in milliseconds to use when backfilling layers on a hit from a slower layer. Defaults to nil (no expiry)."
    ]
  ])}
  """

  @behaviour Cache.Strategy

  @opts_definition [
    on_fetch: [
      type: {:or, [:mfa, {:fun, 1}]},
      doc: "Optional fetch callback for cache miss."
    ],
    backfill_ttl: [
      type: {:or, [:pos_integer, nil]},
      doc: "TTL for backfilled entries."
    ]
  ]

  @impl Cache.Strategy
  def opts_definition, do: @opts_definition

  @impl Cache.Strategy
  def child_spec({cache_name, _layers, _adapter_opts}) do
    %{
      id: :"#{cache_name}_multi_layer",
      start: {Agent, :start_link, [fn -> :ok end, [name: :"#{cache_name}_multi_layer"]]}
    }
  end

  @impl Cache.Strategy
  def get(cache_name, key, layers, adapter_opts) do
    backfill_ttl = adapter_opts[:backfill_ttl]

    case get_from_layers(cache_name, key, layers, adapter_opts, []) do
      {:hit, value, layers_to_backfill} ->
        backfill_layers(cache_name, key, layers_to_backfill, value, backfill_ttl)
        {:ok, value}

      :miss ->
        fetch_on_miss(cache_name, key, layers, adapter_opts)
    end
  end

  @impl Cache.Strategy
  def put(cache_name, key, ttl, value, layers, adapter_opts) do
    reversed = Enum.reverse(layers)
    put_to_layers(cache_name, key, ttl, value, reversed, adapter_opts)
  end

  @impl Cache.Strategy
  def delete(cache_name, key, layers, _adapter_opts) do
    Enum.reduce_while(layers, :ok, fn layer, _acc ->
      case layer_delete(cache_name, key, layer) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp get_from_layers(_cache_name, _key, [], _adapter_opts, _visited), do: :miss

  defp get_from_layers(cache_name, key, [layer | rest], adapter_opts, visited) do
    case layer_get(cache_name, key, layer) do
      {:ok, nil} ->
        get_from_layers(cache_name, key, rest, adapter_opts, [layer | visited])

      {:ok, value} ->
        {:hit, value, visited}

      {:error, _} ->
        get_from_layers(cache_name, key, rest, adapter_opts, [layer | visited])
    end
  end

  defp fetch_on_miss(cache_name, key, layers, adapter_opts) do
    on_fetch = adapter_opts[:on_fetch]

    if is_nil(on_fetch) do
      {:ok, nil}
    else
      case invoke_callback(on_fetch, [key]) do
        {:ok, value} ->
          backfill_ttl = adapter_opts[:backfill_ttl]
          backfill_layers(cache_name, key, layers, value, backfill_ttl)
          {:ok, value}

        {:error, _} = error ->
          error
      end
    end
  end

  defp put_to_layers(_cache_name, _key, _ttl, _value, [], _adapter_opts), do: :ok

  defp put_to_layers(cache_name, key, ttl, value, [layer | rest], adapter_opts) do
    case layer_put(cache_name, key, ttl, value, layer) do
      :ok -> put_to_layers(cache_name, key, ttl, value, rest, adapter_opts)
      {:error, _} = error -> error
    end
  end

  defp backfill_layers(_cache_name, _key, [], _value, _ttl), do: :ok

  defp backfill_layers(cache_name, key, [layer | rest], value, ttl) do
    layer_put(cache_name, key, ttl, value, layer)
    backfill_layers(cache_name, key, rest, value, ttl)
  end

  defp layer_get(_cache_name, key, layer) when is_atom(layer) do
    if cache_module?(layer) do
      layer.get(key)
    else
      {:ok, nil}
    end
  end

  defp layer_put(_cache_name, key, ttl, value, layer) when is_atom(layer) do
    if cache_module?(layer) do
      layer.put(key, ttl, value)
    else
      :ok
    end
  end

  defp layer_delete(_cache_name, key, layer) when is_atom(layer) do
    if cache_module?(layer) do
      layer.delete(key)
    else
      :ok
    end
  end

  defp cache_module?(module) do
    function_exported?(module, :get, 1) and function_exported?(module, :put, 2)
  end

  defp invoke_callback({module, function, args}, extra_args) do
    apply(module, function, args ++ extra_args)
  end

  defp invoke_callback(fun, args) when is_function(fun) do
    apply(fun, args)
  end
end
