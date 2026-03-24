defmodule Cache.Counter do
  @opts_definition [
    initial_size: [
      type: :pos_integer,
      default: 1,
      doc: "Number of counter slots to pre-allocate"
    ],

    write_concurrency: [
      type: :boolean,
      default: false,
      doc: "Enable concurrent writes to different counter slots. When false, all writes serialize through a single process."
    ]
  ]

  @moduledoc """
  Atomic integer counter adapter backed by Erlang's `:counters` module.

  Counter values are stored in a lock-free `:counters` array. The array reference
  is stored in `:persistent_term` so all processes can access it without a
  process round-trip.

  The slot index for a key is determined as follows:

  - **Integer key** — used directly as the 0-based slot index (`key + 1`
    internally, since `:counters` is 1-based). Callers control exactly which
    slot is accessed with no hashing involved.
  - **Atom / string key** — index computed deterministically via
    `:erlang.phash2(key, size) + 1`, eliminating any key-to-index bookkeeping
    and the race conditions that come with it.

  ## Behaviour

  - `put/4` accepts only `1` or `-1` as values, acting as increment or decrement.
    Any other value returns an error.
  - `get/2` accepts only a non-negative integer key and returns the current
    integer value for that slot. Returns `0` if the slot has never been incremented.
  - `delete/2` zeroes the counter slot for the given key. Because multiple keys
    may hash to the same slot (especially with a small `initial_size`), deleting
    one key resets the slot shared by all keys that collide with it.
  - `increment/1,2` and `decrement/1,2` are injected into consumer modules via `use`.

  ## Hash collisions

  With a small `initial_size`, distinct keys may map to the same counter slot.
  Operations on colliding keys are summed in that shared slot. Increase
  `initial_size` to reduce collision probability.

  ## Options
  #{NimbleOptions.docs(@opts_definition)}

  ## Example

  ```elixir
  defmodule MyApp.Cache do
    use Cache,
      adapter: Cache.Counter,
      name: :my_app_counter_cache,
      opts: [initial_size: 32]
  end

  MyApp.Cache.increment(:page_views)
  MyApp.Cache.decrement(:active_users)
  {:ok, count} = MyApp.Cache.get(:page_views)
  ```
  """

  use Task, restart: :permanent

  @behaviour Cache

  @ref_key :__counter_ref__
  @size_key :__counter_size__

  defmacro __using__(_opts) do
    quote do
      @doc """
      Atomically increments the counter for the given key by `step` (default 1).
      """
      def increment(key, step \\ 1) do
        key = maybe_sandbox_key(key)
        @cache_adapter.increment(@cache_name, key, step)
      end

      @doc """
      Atomically decrements the counter for the given key by `step` (default 1).
      """
      def decrement(key, step \\ 1) do
        key = maybe_sandbox_key(key)
        @cache_adapter.decrement(@cache_name, key, step)
      end
    end
  end

  @impl Cache
  def opts_definition, do: @opts_definition

  @impl Cache
  def start_link(opts) do
    Task.start_link(fn ->
      cache_name = opts[:table_name]
      initial_size = opts[:initial_size] || 1
      counters_opts = if opts[:write_concurrency], do: [:atomics, :write_concurrency], else: [:atomics]
      ref = :counters.new(initial_size, counters_opts)
      :persistent_term.put({cache_name, @ref_key}, ref)
      :persistent_term.put({cache_name, @size_key}, initial_size)
      Process.hibernate(Function, :identity, [nil])
    end)
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: "#{cache_name}_elixir_cache_counter",
      start: {Cache.Counter, :start_link, [Keyword.put(opts, :table_name, cache_name)]}
    }
  end

  @impl Cache
  @spec get(atom, atom | String.t() | non_neg_integer, Keyword.t()) :: ErrorMessage.t_res(integer | nil)
  def get(cache_name, key, _opts \\ [])

  def get(cache_name, key, _opts) when is_integer(key) and key >= 0 do
    size = get_size(cache_name)

    if key < size do
      ref = get_ref(cache_name)
      count = :counters.get(ref, key + 1)
      {:ok, (if count === 0, do: nil, else: count)}
    else
      {:error, ErrorMessage.bad_request("integer key #{key} is out of bounds (initial_size: #{size})", %{cache: cache_name, key: key})}
    end
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  def get(_cache_name, key, _opts) do
    {:error, ErrorMessage.bad_request("Cache.Counter.get/3 requires a non_neg_integer key, got: #{inspect(key)}")}
  end

  @impl Cache
  @spec put(atom, atom | String.t() | non_neg_integer, pos_integer | nil, 1 | -1, Keyword.t()) ::
          ErrorMessage.t_ok_res()
  def put(cache_name, key, ttl \\ nil, value, opts \\ [])

  def put(cache_name, key, _ttl, value, _opts) when value in [1, -1] do
    ref = get_ref(cache_name)
    :counters.add(ref, compute_index(ref, key), value)
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  def put(_cache_name, _key, _ttl, value, _opts) do
    {:error,
     ErrorMessage.unprocessable_entity(
       "put/4 value must be 1 or -1 for Cache.Counter, got: #{inspect(value)}"
     )}
  end

  @impl Cache
  @spec delete(atom, atom | String.t() | non_neg_integer, Keyword.t()) :: ErrorMessage.t_ok_res()
  def delete(cache_name, key, _opts \\ []) do
    ref = get_ref(cache_name)
    :counters.put(ref, compute_index(ref, key), 0)
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  @spec increment(atom, atom | String.t() | non_neg_integer, pos_integer) :: ErrorMessage.t_ok_res()
  def increment(cache_name, key, step \\ 1) do
    ref = get_ref(cache_name)
    :counters.add(ref, compute_index(ref, key), step)
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  @spec decrement(atom, atom | String.t() | non_neg_integer, pos_integer) :: ErrorMessage.t_ok_res()
  def decrement(cache_name, key, step \\ 1) do
    ref = get_ref(cache_name)
    :counters.add(ref, compute_index(ref, key), -step)
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  defp get_ref(cache_name) do
    :persistent_term.get({cache_name, @ref_key})
  end

  defp get_size(cache_name) do
    :persistent_term.get({cache_name, @size_key})
  end

  defp compute_index(_ref, key) when is_integer(key), do: key + 1

  defp compute_index(ref, key) do
    :erlang.phash2(key, :counters.info(ref).size) + 1
  end
end
