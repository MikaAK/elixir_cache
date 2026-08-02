defmodule Cache.MultiLayer.Coordinator do
  @moduledoc """
  Per-node coordinator for cross-node layer coherence in `Cache.MultiLayer`.

  One coordinator runs per MultiLayer cache per node. Each joins a `:pg`
  group named after the cache, so group membership doubles as a registry of
  which nodes currently run the cache. When a cache is configured with
  `broadcast_mode`, writes on one node notify every other member, which then
  applies the change to its own node-local layers (`broadcast_layers`):

  - `:invalidate` — remote nodes delete the key from their local layers; the
    next read falls through to the shared slower layer and backfills fresh.
    Message cost is the key only. Prefer this for large values or many-node
    clusters.
  - `:replicate` — remote nodes write the new value into their local layers
    immediately. Costs a full value copy per member; prefer only for small
    values whose next read must not pay a fallthrough.

  Delivery is best-effort (`send/2` to pg members, no acks). A member that
  misses a message (netsplit, restart races) serves its stale local entry
  until that entry's TTL expires — configure `backfill_ttl` (and layer TTLs)
  as the correctness floor; the broadcast is only the fast path.
  """

  use GenServer

  @pg_scope :cache_multi_layer_coordinator

  def start_link(cache_name) do
    GenServer.start_link(__MODULE__, cache_name, name: name(cache_name))
  end

  def child_spec(cache_name) do
    %{
      id: :"#{cache_name}_multi_layer",
      start: {__MODULE__, :start_link, [cache_name]}
    }
  end

  @doc "pg-tracked coordinator pids for this cache across the cluster."
  @spec members(atom()) :: [pid()]
  def members(cache_name) do
    :pg.get_members(@pg_scope, cache_name)
  end

  @doc """
  Notify every other node's coordinator for `cache_name`.

  Excludes `self()`'s node's coordinator by pid so the writing node never
  re-applies its own (already fresh) write.
  """
  @spec broadcast(atom(), tuple()) :: :ok
  def broadcast(cache_name, message) do
    local = Process.whereis(name(cache_name))

    Enum.each(members(cache_name), fn member ->
      if member !== local, do: send(member, message)
    end)
  end

  @impl GenServer
  def init(cache_name) do
    {:ok, join_and_monitor_scope(cache_name)}
  end

  @impl GenServer
  def handle_info({:multi_layer_invalidate, key, layers}, state) do
    Enum.each(layers, &(&1.delete(key)))
    {:noreply, state}
  end

  def handle_info({:multi_layer_replicate, key, ttl, value, layers}, state) do
    Enum.each(layers, &(&1.put(key, ttl, value)))
    {:noreply, state}
  end

  # The pg scope died (it is unlinked/unsupervised — this library has no
  # application tree to own it). A restarted scope comes back with empty
  # membership, so every coordinator must re-join or broadcasts silently
  # stop reaching this node.
  def handle_info(
        {:DOWN, scope_ref, :process, _pid, _reason},
        %{scope_ref: scope_ref, cache_name: cache_name}
      ) do
    {:noreply, join_and_monitor_scope(cache_name)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp name(cache_name), do: :"#{cache_name}_multi_layer_coordinator"

  defp join_and_monitor_scope(cache_name) do
    scope_pid = ensure_pg_scope()
    :ok = :pg.join(@pg_scope, cache_name, self())
    %{cache_name: cache_name, scope_ref: Process.monitor(scope_pid)}
  end

  # :pg.start/1 (not start_link) — linking would tie the scope's life to
  # whichever coordinator happened to start it first, killing membership for
  # every cache on the node when that one coordinator dies.
  defp ensure_pg_scope do
    case :pg.start(@pg_scope) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
end
