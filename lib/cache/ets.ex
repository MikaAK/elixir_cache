defmodule Cache.ETS do
  @opts_definition [
    write_concurrency: [
      type: :boolean,
      doc: "Enable write concurrency"
    ],
    read_concurrency: [
      type: :boolean,
      doc: "Enable read concurrency"
    ],
    decentralized_counters: [
      type: :boolean,
      doc: "Use decentralized counters"
    ],
    enable_ttl?: [
      type: :pos_integer,
      doc: "Enables TTLs"
    ],
    compressed: [
      type: :boolean,
      doc: "Enable ets compression"
    ]
  ]

  @moduledoc """
  ETS adapter so that we can use ets as a cache

  ## Options
  #{NimbleOptions.docs(@opts_definition)}
  """

  use Task, restart: :permanent

  @behaviour Cache

  @impl Cache
  def opts_definition, do: @opts_definition

  def start_link(opts) do
    Task.start_link(fn ->
      table_name = opts[:table_name]

      opts =
        opts
        |> Keyword.delete(:table_name)
        |> Kernel.++([:public, :named_table])

      opts =
        if opts[:compressed] do
          Keyword.delete(opts, :compressed) ++ [:compressed]
        else
          opts
        end

      :ets.new(table_name, opts)

      Process.hibernate(Function, :identity, [nil])
    end)
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: "#{cache_name}_elixir_cache_ets",
      start: {Cache.ETS, :start_link, [Keyword.put(opts, :table_name, cache_name)]}
    }
  end

  @impl Cache
  def get(cache_name, key, _opts \\ []) do
    case :ets.lookup(cache_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:ok, nil}
    end
  end

  @impl Cache
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ []) do
    :ets.insert(cache_name, {key, value})

    :ok
  end

  @impl Cache
  def delete(cache_name, key, _opts \\ []) do
    :ets.delete(cache_name, key)

    :ok
  end
end
