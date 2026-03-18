defmodule Cache.Counter do
  @opts_definition [
    initial_size: [
      type: :pos_integer,
      default: 16,
      doc: "Initial number of counter slots to pre-allocate"
    ]
  ]

  @moduledoc """
  Atomic integer counter adapter backed by Erlang's `:counters` module.

  Counter values are stored in a lock-free `:counters` array. The array reference
  and the key-to-index mapping are stored in `:persistent_term` so all processes
  can access them without a process round-trip.

  ## Behaviour

  - `put/4` accepts only `1` or `-1` as values, acting as increment or decrement.
    Any other value returns an error.
  - `get/2` returns the current integer value for a key, or `nil` if the key is unknown.
  - `delete/2` removes a key from the index map and zeroes its counter slot.
  - `increment/1,2` and `decrement/1,2` are injected into consumer modules via `use`.

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
  @index_map_key :__counter_index_map__

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
      initial_size = opts[:initial_size] || 16
      ref = :counters.new(initial_size, [:atomics])
      :persistent_term.put({cache_name, @ref_key}, ref)
      :persistent_term.put({cache_name, @index_map_key}, %{})
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
  @spec get(atom, atom | String.t(), Keyword.t()) :: ErrorMessage.t_res(integer | nil)
  def get(cache_name, key, _opts \\ []) do
    index_map = get_index_map(cache_name)

    case Map.get(index_map, key) do
      nil ->
        {:ok, nil}

      index ->
        ref = get_ref(cache_name)
        {:ok, :counters.get(ref, index)}
    end
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  @impl Cache
  @spec put(atom, atom | String.t(), pos_integer | nil, 1 | -1, Keyword.t()) ::
          :ok | ErrorMessage.t()
  def put(cache_name, key, ttl \\ nil, value, opts \\ [])

  def put(cache_name, key, _ttl, value, _opts) when value in [1, -1] do
    {index, ref} = get_or_create_index(cache_name, key)
    :counters.add(ref, index, value)
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
  @spec delete(atom, atom | String.t(), Keyword.t()) :: :ok | ErrorMessage.t()
  def delete(cache_name, key, _opts \\ []) do
    index_map = get_index_map(cache_name)

    case Map.get(index_map, key) do
      nil ->
        :ok

      index ->
        ref = get_ref(cache_name)
        :counters.put(ref, index, 0)
        updated_map = Map.delete(index_map, key)
        :persistent_term.put({cache_name, @index_map_key}, updated_map)
        :ok
    end
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  @spec increment(atom, atom | String.t(), pos_integer) :: :ok | ErrorMessage.t()
  def increment(cache_name, key, step \\ 1) do
    {index, ref} = get_or_create_index(cache_name, key)
    :counters.add(ref, index, step)
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  @spec decrement(atom, atom | String.t(), pos_integer) :: :ok | ErrorMessage.t()
  def decrement(cache_name, key, step \\ 1) do
    {index, ref} = get_or_create_index(cache_name, key)
    :counters.add(ref, index, -step)
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  defp get_ref(cache_name) do
    :persistent_term.get({cache_name, @ref_key})
  end

  defp get_index_map(cache_name) do
    :persistent_term.get({cache_name, @index_map_key}, %{})
  end

  defp get_or_create_index(cache_name, key) do
    index_map = get_index_map(cache_name)

    case Map.get(index_map, key) do
      nil ->
        old_ref = get_ref(cache_name)
        old_size = :counters.info(old_ref).size
        new_size = old_size + 1
        new_ref = :counters.new(new_size, [:atomics])

        Enum.each(1..old_size, fn index ->
          :counters.put(new_ref, index, :counters.get(old_ref, index))
        end)

        new_index = new_size
        updated_map = Map.put(index_map, key, new_index)
        :persistent_term.put({cache_name, @ref_key}, new_ref)
        :persistent_term.put({cache_name, @index_map_key}, updated_map)
        {new_index, new_ref}

      index ->
        {index, get_ref(cache_name)}
    end
  end
end
