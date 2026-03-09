defmodule Cache.HashRing.RingMonitor do
  @moduledoc false

  use GenServer

  @libring_ets_prefix "libring_"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec previous_rings(atom()) :: [HashRing.t()]
  def previous_rings(cache_name) do
    table = history_table_name(cache_name)

    case :ets.whereis(table) do
      :undefined ->
        []

      _ ->
        case :ets.lookup(table, :previous_rings) do
          [{:previous_rings, rings}] -> rings
          [] -> []
        end
    end
  end

  @impl GenServer
  def init(opts) do
    cache_name = Keyword.fetch!(opts, :cache_name)
    ring_name = Keyword.fetch!(opts, :ring_name)
    history_size = Keyword.get(opts, :history_size, 3)
    node_blacklist = Keyword.get(opts, :node_blacklist, [~r/^remsh.*$/, ~r/^rem-.*$/])
    node_whitelist = Keyword.get(opts, :node_whitelist, [])

    table = :ets.new(history_table_name(cache_name), [:set, :public, :named_table])
    :ets.insert(table, {:previous_rings, []})

    :ok = :net_kernel.monitor_nodes(true, node_type: :all)

    {:ok,
     %{
       table: table,
       ring_name: ring_name,
       history_size: history_size,
       node_blacklist: node_blacklist,
       node_whitelist: node_whitelist
     }}
  end

  @impl GenServer
  def handle_info({event, node, _info}, state)
      when event in [:nodeup, :nodedown] do
    unless HashRing.Utils.ignore_node?(node, state.node_blacklist, state.node_whitelist) do
      snapshot_ring(state)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp snapshot_ring(%{table: table, ring_name: ring_name, history_size: history_size}) do
    libring_table = :"#{@libring_ets_prefix}#{ring_name}"

    with [{:ring, current_ring}] <- safe_ets_lookup(libring_table, :ring) do
      [{:previous_rings, existing}] = :ets.lookup(table, :previous_rings)

      updated = Enum.take([current_ring | existing], history_size)

      :ets.insert(table, {:previous_rings, updated})
    end
  end

  defp safe_ets_lookup(table, key) do
    :ets.lookup(table, key)
  rescue
    _ -> []
  end

  @spec history_table_name(atom()) :: atom()
  def history_table_name(cache_name), do: :"#{cache_name}_ring_history"
end
