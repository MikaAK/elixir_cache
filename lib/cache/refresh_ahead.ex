defmodule Cache.RefreshAhead do
  @moduledoc """
  Refresh-ahead caching strategy that proactively refreshes values before they expire.

  Values are stored with a timestamp. On `get`, if the value is within the
  refresh window (i.e. `now - inserted_at >= ttl - refresh_before`), the current
  value is returned immediately and an async `Task` is spawned to refresh it.

  Only keys that are actively read get refreshed — unread keys naturally expire
  from the underlying adapter.

  ## Usage

  ```elixir
  defmodule MyApp.Cache do
    use Cache,
      adapter: {Cache.RefreshAhead, Cache.Redis},
      name: :my_cache,
      opts: [
        uri: "redis://localhost:6379",
        refresh_before: :timer.seconds(30)
      ]

    def refresh(key) do
      {:ok, fetch_fresh_value(key)}
    end
  end
  ```

  ## Options

  #{NimbleOptions.docs([
    refresh_before: [
      type: :pos_integer,
      required: true,
      doc: "Milliseconds before TTL expiry at which to trigger a background refresh."
    ],
    on_refresh: [
      type: {:or, [:mfa, {:fun, 1}]},
      doc: "Optional refresh callback. If not provided, the cache module must define `refresh/1`."
    ],
    lock_node_whitelist: [
      type: {:or, [:atom, {:list, :atom}]},
      doc: "Optional node whitelist for distributed refresh locks. Defaults to all connected nodes."
    ]
  ])}

  ## How It Works

  1. `put/5` wraps the value as `{value, inserted_at_ms, ttl_ms}` before delegating.
  2. `get/4` unwraps the tuple. If `now - inserted_at >= ttl - refresh_before`,
     a background `Task` is spawned to call the refresh callback with the key.
  3. A per-cache ETS deduplication table (`:<name>_refresh_tracker`) prevents
     multiple concurrent refresh tasks for the same key.
  4. On successful refresh, `put/5` is called with the new value and the same TTL,
     resetting the inserted_at timestamp.

  > **Note**: When `sandbox?: true`, values are stored unwrapped. Refresh logic
  > is bypassed entirely.
  """

  @behaviour Cache.Strategy

  @opts_definition [
    refresh_before: [
      type: :pos_integer,
      required: true,
      doc: "Milliseconds before TTL expiry to trigger a background refresh."
    ],
    on_refresh: [
      type: {:or, [:mfa, {:fun, 1}]},
      doc: "Optional refresh callback override."
    ],
    lock_node_whitelist: [
      type: {:or, [:atom, {:list, :atom}]},
      doc: "Optional node whitelist for distributed refresh locks."
    ]
  ]

  @impl Cache.Strategy
  def opts_definition, do: @opts_definition

  @impl Cache.Strategy
  def child_spec({cache_name, underlying_adapter, adapter_opts}) do
    tracker_name = tracker_name(cache_name)

    underlying_adapter_opts =
      validate_underlying_opts(
        underlying_adapter,
        Keyword.drop(adapter_opts, [:refresh_before, :on_refresh, :lock_node_whitelist, :__cache_module__])
      )

    %{
      id: :"#{cache_name}_refresh_ahead_supervisor",
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [
           [
             underlying_adapter.child_spec({cache_name, underlying_adapter_opts}),
             %{
               id: :"#{cache_name}_refresh_tracker",
               start: {__MODULE__, :start_tracker, [tracker_name]}
             }
           ],
           [strategy: :one_for_one]
         ]}
    }
  end

  @doc false
  def start_tracker(tracker_name) do
    if :ets.whereis(tracker_name) === :undefined do
      :ets.new(tracker_name, [:set, :public, :named_table])
    end

    Task.start_link(fn -> Process.hibernate(Function, :identity, [nil]) end)
  end

  @impl Cache.Strategy
  def get(cache_name, key, underlying_adapter, adapter_opts) do

    underlying_opts =
      validate_underlying_opts(
        underlying_adapter,
        Keyword.drop(adapter_opts, [:refresh_before, :on_refresh, :lock_node_whitelist, :__cache_module__])
      )

    compression_level = underlying_opts[:compression_level]

    case underlying_adapter.get(cache_name, key, underlying_opts) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, encoded} ->
        case Cache.TermEncoder.decode(encoded) do
          {value, inserted_at, ttl} ->
            maybe_refresh_async(
              cache_name, key, value, inserted_at, ttl,
              underlying_adapter, adapter_opts, compression_level
            )
            {:ok, value}

          value ->
            {:ok, value}
        end

      {:error, _} = error ->
        error
    end
  end

  @impl Cache.Strategy
  def put(cache_name, key, ttl, value, underlying_adapter, adapter_opts) do

    underlying_opts =
      validate_underlying_opts(
        underlying_adapter,
        Keyword.drop(adapter_opts, [:refresh_before, :on_refresh, :lock_node_whitelist, :__cache_module__])
      )

    compression_level = underlying_opts[:compression_level]
    inserted_at = System.monotonic_time(:millisecond)
    wrapped = Cache.TermEncoder.encode({value, inserted_at, ttl}, compression_level)
    underlying_adapter.put(cache_name, key, ttl, wrapped, underlying_opts)
  end

  @impl Cache.Strategy
  def delete(cache_name, key, underlying_adapter, adapter_opts) do

    underlying_opts =
      validate_underlying_opts(
        underlying_adapter,
        Keyword.drop(adapter_opts, [:refresh_before, :on_refresh, :lock_node_whitelist, :__cache_module__])
      )

    tracker = tracker_name(cache_name)
    safe_ets_delete(tracker, key)
    underlying_adapter.delete(cache_name, key, underlying_opts)
  end

  defp maybe_refresh_async(cache_name, key, _value, inserted_at, ttl, underlying_adapter, adapter_opts, compression_level)
       when is_integer(ttl) do
    refresh_before = adapter_opts[:refresh_before]
    now = System.monotonic_time(:millisecond)
    age = now - inserted_at

    if age >= ttl - refresh_before do
      maybe_spawn_refresh(cache_name, key, ttl, underlying_adapter, adapter_opts, compression_level)
    end
  end

  defp maybe_refresh_async(_cache_name, _key, _value, _inserted_at, _ttl, _underlying_adapter, _adapter_opts, _compression_level),
    do: :ok

  defp maybe_spawn_refresh(cache_name, key, ttl, underlying_adapter, adapter_opts, compression_level) do
    tracker = tracker_name(cache_name)

    if safe_ets_insert_new(tracker, {key, true}) do
      Task.start(fn ->
        lock_resource = {:refresh_ahead_lock, cache_name, key}
        lock_id = {lock_resource, self()}
        lock_nodes = lock_nodes(adapter_opts[:lock_node_whitelist])

        try do
          if safe_global_set_lock(lock_id, lock_nodes) do
            on_refresh = adapter_opts[:on_refresh]
            cache_module = adapter_opts[:__cache_module__]

            case invoke_refresh(on_refresh, cache_module, key) do
              {:ok, new_value} ->
                underlying_opts =
                  Keyword.drop(adapter_opts, [
                    :refresh_before,
                    :on_refresh,
                    :lock_node_whitelist,
                    :__cache_module__
                  ])

                new_inserted_at = System.monotonic_time(:millisecond)
                wrapped = Cache.TermEncoder.encode({new_value, new_inserted_at, ttl}, compression_level)
                underlying_adapter.put(cache_name, key, ttl, wrapped, underlying_opts)

              {:error, _} ->
                :ok
            end
          end
        after
          safe_ets_delete(tracker, key)
        end
      end)
    end
  end

  defp invoke_refresh(nil, cache_module, key) when is_atom(cache_module) and not is_nil(cache_module) do
    cache_module.refresh(key)
  rescue
    UndefinedFunctionError ->
      {:error,
       ErrorMessage.internal_server_error(
         "Cache.RefreshAhead requires a refresh/1 callback on #{inspect(cache_module)} or an on_refresh opt",
         %{cache_module: cache_module, key: key}
       )}
  end

  defp invoke_refresh(nil, cache_module, key) do
    {:error,
     ErrorMessage.internal_server_error(
       "Cache.RefreshAhead requires a refresh/1 callback or an on_refresh opt",
       %{cache_module: cache_module, key: key}
     )}
  end

  defp invoke_refresh({module, function, args}, _cache_name, key) do
    apply(module, function, args ++ [key])
  end

  defp invoke_refresh(fun, _cache_name, key) when is_function(fun, 1) do
    fun.(key)
  end

  defp safe_ets_insert_new(tracker, record) do
    :ets.insert_new(tracker, record)
  rescue
    _ -> false
  end

  defp safe_ets_delete(tracker, key) do
    :ets.delete(tracker, key)
  rescue
    _ -> :ok
  end

  defp safe_global_set_lock(lock_id, lock_nodes) do
    :global.set_lock(lock_id, lock_nodes, 0)
  rescue
    _ -> false
  end

  defp lock_nodes(lock_node_whitelist) do
    connected_nodes = [Node.self() | Node.list()]

    nodes =
      case lock_node_whitelist do
        nil -> connected_nodes
        node when is_atom(node) -> [node]
        whitelist when is_list(whitelist) -> whitelist
      end

    nodes
    |> Enum.filter(&(&1 in connected_nodes))
    |> Kernel.++([Node.self()])
    |> Enum.uniq()
  end

  defp validate_underlying_opts(adapter, opts) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :opts_definition, 0) do
      NimbleOptions.validate!(opts, adapter.opts_definition())
    else
      opts
    end
  end

  defp tracker_name(cache_name), do: :"#{cache_name}_refresh_tracker"
end
