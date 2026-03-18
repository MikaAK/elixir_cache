defmodule Cache.PersistentTerm do
  @moduledoc """
  `:persistent_term` adapter for storing rarely-written, frequently-read cached values.

  This adapter stores values in Erlang's `:persistent_term` storage, which provides
  extremely fast read access at the cost of more expensive writes and deletes.
  It is best suited for configuration values or other data that changes infrequently.

  TTL is not supported — values persist until explicitly deleted.

  ## Example

  ```elixir
  defmodule MyApp.Cache do
    use Cache,
      adapter: Cache.PersistentTerm,
      name: :my_app_persistent_cache,
      opts: []
  end
  ```
  """

  use Task, restart: :permanent

  @behaviour Cache

  @impl Cache
  def opts_definition, do: []

  @impl Cache
  def start_link(opts) do
    Task.start_link(fn ->
      _table_name = opts[:table_name]
      Process.hibernate(Function, :identity, [nil])
    end)
  end

  @impl Cache
  def child_spec({cache_name, opts}) do
    %{
      id: "#{cache_name}_elixir_cache_persistent_term",
      start: {Cache.PersistentTerm, :start_link, [Keyword.put(opts, :table_name, cache_name)]}
    }
  end

  @impl Cache
  @spec get(atom, atom | String.t(), Keyword.t()) :: ErrorMessage.t_res(any)
  def get(cache_name, key, _opts \\ []) do
    {:ok, :persistent_term.get({cache_name, key}, nil)}
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  @impl Cache
  @spec put(atom, atom | String.t(), pos_integer | nil, any, Keyword.t()) :: :ok | ErrorMessage.t()
  def put(cache_name, key, _ttl \\ nil, value, _opts \\ []) do
    :persistent_term.put({cache_name, key}, value)
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end

  @impl Cache
  @spec delete(atom, atom | String.t(), Keyword.t()) :: :ok | ErrorMessage.t()
  def delete(cache_name, key, _opts \\ []) do
    :persistent_term.erase({cache_name, key})
    :ok
  rescue
    exception ->
      {:error, ErrorMessage.internal_server_error(Exception.message(exception), %{cache: cache_name, key: key})}
  end
end
