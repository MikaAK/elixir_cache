defmodule Cache.ConCache do
  @opts_definition [
    acquire_lock_timeout: [type: :pos_integer, default: 5000],
    touch_on_read: [type: :boolean, default: false],
    global_ttl: [type: {:or, [:pos_integer, {:in, [:infinity]}]}, default: :timer.minutes(30)],
    ttl_check_interval: [type: {:or, [:pos_integer, {:in, [false]}]}, default: :timer.minutes(1)],
    dirty?: [
      type: :boolean,
      default: true,
      doc: "Use dirty_put instead of locking to put, enabled by default"
    ],
    ets_options: [
      type: {:custom, Cache.ETS, :opts_definition, []},
      doc: "https://www.erlang.org/doc/man/ets.html#new-2"
    ]
  ]
  @moduledoc """
  ETS Based cache https://github.com/sasa1977/con_cache

  Takes the following options:

   #{NimbleOptions.docs(@opts_definition)}
  """

  @behaviour Cache

  @type opts :: [
          name: atom,
          pid: pid,
          global_ttl: non_neg_integer | :infinity,
          acquire_lock_timeout: pos_integer,
          touch_on_read: boolean | nil,
          ttl_check_interval: non_neg_integer() | false,
          ets_options: [ets_option()]
        ]

  @type ets_option ::
          :named_table
          | :compressed
          | {:heir, pid()}
          | {:write_concurrency, boolean()}
          | {:read_concurrency, boolean()}
          | :ordered_set
          | :set
          | :bag
          | :duplicate_bag
          | {:name, atom()}

  defmacro __using__(_opts) do
    quote do
      def get_or_store(key, ttl, store_fun) do
        @cache_adapter.get_or_store(@cache_name, key, ttl, store_fun)
      end

      def dirty_get_or_store(key, store_fun) do
        @cache_adapter.dirty_get_or_store(@cache_name, key, store_fun)
      end
    end
  end

  @impl Cache
  def opts_definition, do: @opts_definition

  @impl Cache
  def start_link(opts) do
    cache_opts =
      opts
      |> Keyword.delete(:dirty?)
      |> Keyword.update(
        :ets_options,
        [:named_table, name: opts[:name]],
        &[:named_table, {:name, opts[:name]} | &1]
      )

    ConCache.start_link(cache_opts)
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: :"con_cache_#{cache_name}",
      start: {Cache.ConCache, :start_link, [Keyword.put(opts, :name, cache_name)]},
      type: :supervisor
    }
  end

  @impl Cache
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ [])

  def put(cache_name, key, nil, value, opts) do
    if is_nil(opts[:dirty?]) or opts[:dirty?] do
      ConCache.dirty_put(cache_name, key, value)
    else
      ConCache.put(cache_name, key, value)
    end
  end

  def put(cache_name, key, ttl, value, opts) do
    item = %ConCache.Item{value: value, ttl: ttl}

    if is_nil(opts[:dirty?]) or opts[:dirty?] do
      ConCache.dirty_put(cache_name, key, item)
    else
      ConCache.put(cache_name, key, item)
    end
  end

  @impl Cache
  def get(cache_name, key, _opts \\ []) do
    {:ok, ConCache.get(cache_name, key)}
  end

  @impl Cache
  def delete(cache_name, key, _opts \\ []) do
    ConCache.delete(cache_name, key)
  end

  @doc """
  Implements a version of get_or_store that locks locally
  so only one process runs `store_fun` at a time.

  Any other processes that miss cache will wait for the first
  caller to finish `store_fun` then will read the result from cache.
  """
  def get_or_store(cache_name, key, ttl, store_fun) do
    ConCache.get_or_store(cache_name, key, fn ->
      %ConCache.Item{value: store_fun.(), ttl: ttl}
    end)
  end

  def dirty_get_or_store(cache_name, key, store_fun) do
    ConCache.dirty_get_or_store(cache_name, key, store_fun)
  end
end
