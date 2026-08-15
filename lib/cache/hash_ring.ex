defmodule Cache.HashRing do
  @moduledoc """
  Consistent hash ring strategy adapter using `libring`.

  This strategy distributes cache keys across Erlang cluster nodes using a
  consistent hash ring. When a key is hashed to the local node, the operation
  is executed directly. When it hashes to a remote node, the operation is
  forwarded via a configurable RPC module (defaults to `:erpc`).

  The ring automatically tracks Erlang node membership using
  `HashRing.Managed` with `monitor_nodes: true`, so nodes joining or leaving
  the cluster are reflected in the ring automatically.

  ## Usage

  ```elixir
  defmodule MyApp.DistributedCache do
    use Cache,
      adapter: {Cache.HashRing, Cache.ETS},
      name: :distributed_cache,
      opts: [read_concurrency: true]
  end
  ```

  ## Options

  #{NimbleOptions.docs([
    ring_opts: [
      type: :keyword_list,
      doc: "Options passed to `HashRing.Worker`, such as `node_blacklist` and `node_whitelist`.",
      default: []
    ],
    node_weight: [
      type: :pos_integer,
      doc: "Number of virtual nodes (shards) per node on the ring. Higher values give more even distribution.",
      default: 128
    ],
    rpc_module: [
      type: :atom,
      doc: "Module used for remote calls. Must implement `call/4` with the same signature as `:erpc.call/4`.",
      default: :erpc
    ]
  ])}

  ## How It Works

  Each node in the cluster starts the same underlying adapter locally. When a
  cache operation is performed:

  1. The key is hashed to determine which node owns it via the consistent ring.
  2. If the owning node is `Node.self()`, the operation is executed locally.
  3. If the owning node is a remote node, the operation is forwarded via the
     configured `rpc_module` (default `:erpc`).

  This ensures that each key is always stored on the same node (with the same
  ring configuration), enabling efficient distributed caching without a
  centralised store.

  ## Read-Repair

  When the ring topology changes (node up/down), some keys will hash to a
  different node. `Cache.HashRing.RingMonitor` snapshots the ring before each
  change, keeping up to `ring_history_size` previous rings.

  On a `get` miss, the previous rings are consulted in order (newest first).
  For each previous ring, if the key hashed to a different (live) node, a
  `get` is attempted there. On a hit:

  1. The value is returned immediately.
  2. It is written to the current owning node (migration).
  3. It is deleted from the old node asynchronously.

  This lazily migrates hot keys after rebalancing without scanning the ring.

  > **Note**: When `sandbox?: true`, the ring is bypassed and all operations
  > are executed locally against the sandbox adapter.
  """

  @behaviour Cache.Strategy

  @strategy_keys [:ring_opts, :node_weight, :rpc_module, :ring_history_size, :__cache_module__]

  @opts_definition [
    ring_opts: [
      type: :keyword_list,
      doc: "Options passed to HashRing.Worker.",
      default: []
    ],
    node_weight: [
      type: :pos_integer,
      doc: "Number of virtual nodes (shards) per node on the ring.",
      default: 128
    ],
    rpc_module: [
      type: :atom,
      doc: "Module used for remote calls (must implement call/4).",
      default: :erpc
    ],
    ring_history_size: [
      type: :pos_integer,
      doc: "Number of previous ring snapshots to keep for read-repair fallback.",
      default: 3
    ]
  ]

  @impl Cache.Strategy
  def opts_definition, do: @opts_definition

  @impl Cache.Strategy
  def child_spec({cache_name, underlying_adapter, adapter_opts}) do
    ring_name = ring_name(cache_name)
    user_ring_opts = adapter_opts[:ring_opts] || []
    ring_opts = Keyword.merge([monitor_nodes: true], user_ring_opts)
    underlying_opts = validate_underlying_opts(underlying_adapter, Keyword.drop(adapter_opts, @strategy_keys))

    managed_ring_spec = %{
      id: ring_name,
      type: :worker,
      start: {HashRing.Worker, :start_link, [[{:name, ring_name} | ring_opts]]}
    }

    ring_monitor_spec = %{
      id: :"#{cache_name}_ring_monitor",
      start:
        {Cache.HashRing.RingMonitor, :start_link,
         [
           [
             cache_name: cache_name,
             ring_name: ring_name,
             history_size: adapter_opts[:ring_history_size] || 3,
             node_blacklist: user_ring_opts[:node_blacklist] || [~r/^remsh.*$/, ~r/^rem-.*$/],
             node_whitelist: user_ring_opts[:node_whitelist] || []
           ]
         ]}
    }

    %{
      id: :"#{cache_name}_hash_ring_supervisor",
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [
           [
             underlying_adapter.child_spec({cache_name, underlying_opts}),
             managed_ring_spec,
             ring_monitor_spec
           ],
           [strategy: :one_for_one]
         ]}
    }
  end

  @impl Cache.Strategy
  def get(cache_name, key, underlying_adapter, adapter_opts) do
    target_node = key_to_node(cache_name, key)
    rpc = adapter_opts[:rpc_module] || :erpc
    underlying_opts = validate_underlying_opts(underlying_adapter, Keyword.drop(adapter_opts, @strategy_keys))

    result =
      if target_node === Node.self() do
        underlying_adapter.get(cache_name, key, underlying_opts)
      else
        rpc.call(target_node, underlying_adapter, :get, [cache_name, key, underlying_opts])
      end

    case result do
      {:ok, nil} ->
        read_repair(cache_name, key, target_node, underlying_adapter, underlying_opts, rpc)

      {:ok, encoded} ->
        {:ok, Cache.TermEncoder.decode(encoded)}

      {:error, _} = error ->
        error
    end
  end

  @impl Cache.Strategy
  def put(cache_name, key, ttl, value, underlying_adapter, adapter_opts) do
    target_node = key_to_node(cache_name, key)
    rpc = adapter_opts[:rpc_module] || :erpc
    underlying_opts = validate_underlying_opts(underlying_adapter, Keyword.drop(adapter_opts, @strategy_keys))
    encoded = Cache.TermEncoder.encode(value, underlying_opts[:compression_level])

    if target_node === Node.self() do
      underlying_adapter.put(cache_name, key, ttl, encoded, underlying_opts)
    else
      rpc.call(target_node, underlying_adapter, :put, [cache_name, key, ttl, encoded, underlying_opts])
    end
  end

  @impl Cache.Strategy
  def delete(cache_name, key, underlying_adapter, adapter_opts) do
    target_node = key_to_node(cache_name, key)
    rpc = adapter_opts[:rpc_module] || :erpc
    underlying_opts = validate_underlying_opts(underlying_adapter, Keyword.drop(adapter_opts, @strategy_keys))

    if target_node === Node.self() do
      underlying_adapter.delete(cache_name, key, underlying_opts)
    else
      rpc.call(target_node, underlying_adapter, :delete, [cache_name, key, underlying_opts])
    end
  end

  defp read_repair(cache_name, key, current_node, underlying_adapter, underlying_opts, rpc) do
    previous_rings = Cache.HashRing.RingMonitor.previous_rings(cache_name)

    result =
      Enum.reduce_while(previous_rings, {:not_found, MapSet.new()}, fn ring, {:not_found, tried} ->
        old_node = HashRing.key_to_node(ring, key)

        cond do
          old_node === current_node ->
            {:cont, {:not_found, tried}}

          MapSet.member?(tried, old_node) ->
            {:cont, {:not_found, tried}}

          true ->
            case rpc_get(rpc, old_node, underlying_adapter, cache_name, key, underlying_opts) do
              {:ok, nil} ->
                {:cont, {:not_found, MapSet.put(tried, old_node)}}

              {:ok, encoded} ->
                {:halt, {:found, encoded, old_node}}

              :unavailable ->
                {:cont, {:not_found, MapSet.put(tried, old_node)}}
            end
        end
      end)

    case result do
      {:found, encoded, old_node} ->
        value = Cache.TermEncoder.decode(encoded)
        migrate_value(cache_name, key, value, current_node, old_node, underlying_adapter, underlying_opts, rpc)
        {:ok, value}

      {:not_found, _tried} ->
        {:ok, nil}
    end
  end

  defp migrate_value(cache_name, key, value, current_node, old_node, underlying_adapter, underlying_opts, rpc) do
    encoded = Cache.TermEncoder.encode(value, underlying_opts[:compression_level])

    if current_node === Node.self() do
      underlying_adapter.put(cache_name, key, nil, encoded, underlying_opts)
    else
      rpc.call(current_node, underlying_adapter, :put, [cache_name, key, nil, encoded, underlying_opts])
    end

    Task.start(fn ->
      rpc.call(old_node, underlying_adapter, :delete, [cache_name, key, underlying_opts])
    end)
  end

  defp rpc_get(rpc, node, adapter, cache_name, key, opts) do
    case rpc.call(node, adapter, :get, [cache_name, key, opts]) do
      {:ok, _} = result -> result
      {:error, _} -> :unavailable
      {:badrpc, _} -> :unavailable
    end
  rescue
    _ -> :unavailable
  catch
    :exit, _ -> :unavailable
  end

  defp key_to_node(cache_name, key) do
    ring = ring_name(cache_name)

    case HashRing.Managed.key_to_node(ring, key) do
      {:error, {:invalid_ring, :no_nodes}} -> Node.self()
      {:error, :no_such_ring} -> Node.self()
      node -> node
    end
  end

  defp validate_underlying_opts(adapter, opts) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :opts_definition, 0) do
      NimbleOptions.validate!(opts, adapter.opts_definition())
    else
      opts
    end
  end

  defp ring_name(cache_name), do: :"#{cache_name}_hash_ring"
end
