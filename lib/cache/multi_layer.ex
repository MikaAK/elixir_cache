defmodule Cache.MultiLayer do
  @moduledoc """
  Multi-layer caching strategy that cascades through multiple cache layers.

  Keys are read from fastest to slowest, with automatic backfill on cache hits
  from slower layers. Writes go slowest-first to avoid polluting fast layers
  with data that failed to persist in slow ones.

  ## Usage

  Every layer is a `use Cache` MODULE — one that is already defined and
  supervised in its own right. Adapters (`Cache.ETS`, `Cache.Redis`) are not
  layers: an adapter is stateless and exports `get/3`/`put/5`, so it has no
  instance to address, while a cache module exports `get/1`/`put/3` and
  carries its own name. Wrap the adapter in a module and list that.

  ```elixir
  defmodule MyApp.Local do
    use Cache, adapter: Cache.ETS, name: :my_app_local, opts: []
  end

  defmodule MyApp.Shared do
    use Cache, adapter: Cache.Redis, name: :my_app_shared, opts: [uri: "redis://localhost"]
  end

  defmodule MyApp.LayeredCache do
    use Cache,
      adapter: {Cache.MultiLayer, [MyApp.Local, MyApp.Shared]},
      name: :layered_cache,
      opts: []
  end
  ```

  Start every layer alongside the cascade, layers first:

  ```elixir
  {Cache, [MyApp.Local, MyApp.Shared, MyApp.LayeredCache]}
  ```

  A layer that is not a cache module raises at startup with the offending
  module named — see `child_spec/1`. Passing an adapter used to be documented
  and silently did nothing, which is the failure this validation exists to
  make impossible.

  ## A cache cannot be its own layer

  Do not list the defining module in its own layer list. Its `get/1` is this
  strategy's `get/4`, so the cascade would call back into itself.

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

  ## Cross-Node Coherence (Optional)

  Node-local fast layers (e.g. `Cache.ETS`) go stale on every node except the
  writer. Setting `broadcast_mode` keeps them coherent: after a successful
  `put`/`delete`, every other node running this cache (tracked via `:pg` —
  see `Cache.MultiLayer.Coordinator`) is notified and applies the change to
  its own `broadcast_layers`.

  ```elixir
  defmodule MyApp.LayeredCache do
    use Cache,
      adapter: {Cache.MultiLayer, [MyApp.EtsLayer, MyApp.RedisCache]},
      name: :layered_cache,
      opts: [
        backfill_ttl: :timer.seconds(30),
        broadcast_mode: :invalidate,
        broadcast_layers: [MyApp.EtsLayer]
      ]
  end
  ```

  `:invalidate` sends only the key — remote nodes drop their local entry and
  lazily re-read through the shared layer. `:replicate` ships the value so
  remote local layers are updated immediately; use it only for small values.
  Delivery is best-effort: always keep `backfill_ttl` (and layer TTLs) as the
  correctness floor for members that miss a message.

  ## Options

  #{NimbleOptions.docs([
    on_fetch: [
      type: {:or, [:mfa, {:fun, 1}]},
      doc: "Optional fetch callback invoked on total cache miss. Receives the key, returns `{:ok, value}` or `{:error, reason}`."
    ],
    backfill_ttl: [
      type: {:or, [:pos_integer, nil]},
      doc: "TTL in milliseconds to use when backfilling layers on a hit from a slower layer. Defaults to nil (no expiry)."
    ],
    broadcast_mode: [
      type: {:in, [:invalidate, :replicate]},
      doc: "Cross-node coherence for writes: `:invalidate` deletes the key from other nodes' `broadcast_layers`; `:replicate` pushes the written value to them. Best-effort delivery."
    ],
    broadcast_layers: [
      type: {:list, :atom},
      doc: "Node-local layer modules the broadcast applies to on other nodes. Required with `broadcast_mode`; must not include the shared (slowest) layer."
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
    ],
    broadcast_mode: [
      type: {:in, [:invalidate, :replicate]},
      doc:
        "Cross-node coherence for writes: :invalidate deletes the key from other nodes' broadcast_layers (next read falls through and backfills fresh); :replicate pushes the written value to them. Best-effort delivery — keep TTLs as the correctness floor."
    ],
    broadcast_layers: [
      type: {:list, :atom},
      doc:
        "Node-local layer modules the broadcast applies to on the other nodes. Required when broadcast_mode is set; must not include the shared (slowest) layer."
    ]
  ]

  @impl Cache.Strategy
  def opts_definition, do: @opts_definition

  @impl Cache.Strategy
  def child_spec({cache_name, layers, _adapter_opts}) do
    validate_layers!(cache_name, layers)

    Cache.MultiLayer.Coordinator.child_spec(cache_name)
  end

  # Layers are `use Cache` MODULES. Anything else — an adapter, a tuple, a
  # typo — is rejected here, at startup, with the offending element named.
  #
  # This is not defensive tidiness: the dispatch below is duck-typed on
  # `get/1`/`put/3`, and its previous no-match branches returned `{:ok, nil}`
  # and `:ok`. Those are SUCCESS shapes. A layer that fails the check would
  # read as a permanent miss and discard every write, and neither is
  # distinguishable from a cold cache and a successful write — so a
  # misconfigured cascade behaved exactly like a working one, forever.
  # Startup is the last place this can still be loud.
  defp validate_layers!(cache_name, layers) do
    Enum.each(layers, fn layer ->
      unless is_atom(layer) and cache_module?(layer) do
        raise ArgumentError, """
        #{inspect(cache_name)}: every Cache.MultiLayer layer must be a `use Cache` module, got:

            #{inspect(layer)}

        An adapter (Cache.ETS, Cache.Redis) is not a layer — it is stateless and
        exports get/3, while a layer must export get/1. Wrap it in a module:

            defmodule MyApp.Local do
              use Cache, adapter: Cache.ETS, name: :my_app_local, opts: []
            end

        then list `MyApp.Local`, and start it alongside the cascade.

        If the module IS a `use Cache` module, it is not compiled or loaded yet —
        check for a typo or a missing dependency.
        """
      end
    end)
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

    with :ok <- put_to_layers(cache_name, key, ttl, value, reversed, adapter_opts) do
      broadcast_write(cache_name, key, ttl, value, adapter_opts)
      :ok
    end
  end

  @impl Cache.Strategy
  def delete(cache_name, key, layers, adapter_opts) do
    result =
      Enum.reduce_while(layers, :ok, fn layer, _acc ->
        case layer_delete(cache_name, key, layer) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)

    with :ok <- result do
      broadcast_delete(cache_name, key, adapter_opts)
      :ok
    end
  end

  # Cross-node coherence (see Cache.MultiLayer.Coordinator). Broadcast only
  # after the local write succeeded — writes go slowest-first, so by the time
  # a remote node reacts (delete + lazy re-read, or replicated put) the shared
  # layer already holds the new value.
  defp broadcast_write(cache_name, key, ttl, value, adapter_opts) do
    case adapter_opts[:broadcast_mode] do
      nil ->
        :ok

      :invalidate ->
        Cache.MultiLayer.Coordinator.broadcast(
          cache_name,
          {:multi_layer_invalidate, key, broadcast_layers!(adapter_opts)}
        )

      :replicate ->
        Cache.MultiLayer.Coordinator.broadcast(
          cache_name,
          {:multi_layer_replicate, key, ttl, value, broadcast_layers!(adapter_opts)}
        )
    end
  end

  defp broadcast_delete(cache_name, key, adapter_opts) do
    if is_nil(adapter_opts[:broadcast_mode]) do
      :ok
    else
      Cache.MultiLayer.Coordinator.broadcast(
        cache_name,
        {:multi_layer_invalidate, key, broadcast_layers!(adapter_opts)}
      )
    end
  end

  defp broadcast_layers!(adapter_opts) do
    adapter_opts[:broadcast_layers] ||
      raise ArgumentError,
            "broadcast_mode is set but broadcast_layers is missing — list the node-local layer modules the broadcast should apply to"
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

  # `validate_layers!/2` has already rejected anything that is not a cache
  # module, so these dispatch directly. No fallback branch: a fallback here
  # could only return a success shape, which is the defect that made a broken
  # layer indistinguishable from a working one.
  defp layer_get(_cache_name, key, layer), do: layer.get(key)

  defp layer_put(_cache_name, key, ttl, value, layer), do: layer.put(key, ttl, value)

  defp layer_delete(_cache_name, key, layer), do: layer.delete(key)

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
