defmodule Cache.DETS do
  @opts_definition [
    ram_file: [
      type: :boolean,
      default: false,
      doc: "Enable RAM File"
    ],

    type: [
      type: {:in, [:bag, :duplicate_bag, :set]},
      default: :set,
      doc: "Data type of DETS cache"
    ],

    file_path: [
      type: :string,
      default: "./",
      doc: "File path to save DETS file at"
    ]
  ]

  @moduledoc """
  DETS adapter so that we can use dets as a cache

  ## Options
  #{NimbleOptions.docs(@opts_definition)}
  """

  use Task, restart: :permanent

  @behaviour Cache

  @impl Cache
  def opts_definition, do: @opts_definition

  @impl Cache
  def start_link(opts) do
    Task.start_link(fn ->
      table_name = opts[:table_name]
      file_path = opts[:file_path]
        |> to_string
        |> create_file_name(table_name)
        |> String.to_charlist

      opts =
        opts
        |> Keyword.drop([:table_name, :file_path])
        |> Kernel.++([access: :read_write, file: file_path])

      {:ok, _} = :dets.open_file(table_name |> IO.inspect, opts) |> IO.inspect

      Process.hibernate(Function, :identity, [nil])
    end)
  end

  defp create_file_name(file_path, table_name) do
    if File.dir?(file_path) do
      Path.join(file_path, "#{table_name}.dets")
    else
      file_path
    end
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: "#{cache_name}_elixir_cache_dets",
      start: {Cache.DETS, :start_link, [Keyword.put(opts, :table_name, cache_name)]}
    }
  end

  @impl Cache
  def get(cache_name, key, _opts \\ []) do
    case :dets.lookup(cache_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:ok, nil}
    end
  end

  @impl Cache
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ []) do
    :dets.insert(cache_name, {key, value})

    :ok
  end

  @impl Cache
  def delete(cache_name, key, _opts \\ []) do
    :dets.delete(cache_name, key)

    :ok
  end
end
