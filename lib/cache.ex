defmodule Cache do
  @moduledoc "#{File.read!("./README.md")}"

  use Supervisor

  @callback child_spec({
              cache_name :: atom,
              cache_opts :: Keyword.t()
            }) :: Supervisor.child_spec() | :supervisor.child_spec()

  @callback opts_definition() :: Keyword.t()

  @callback start_link(
    cache_opts :: Keyword.t()
  ) :: {:ok, pid()} | {:error, {:already_started, pid()} | {:shutdown, term()} | term()} | :ignore

  @callback put(cache_name :: atom, key :: atom | String.t(), ttl :: pos_integer, value :: any) ::
              :ok | ErrorMessage.t()
  @callback put(
              cache_name :: atom,
              key :: atom | String.t(),
              ttl :: pos_integer,
              value :: any,
              Keyword.t()
            ) :: :ok | ErrorMessage.t()

  @callback get(cache_name :: atom, key :: atom | String.t()) :: ErrorMessage.t_res(any)
  @callback get(cache_name :: atom, key :: atom | String.t(), Keyword.t()) ::
              ErrorMessage.t_res(any)

  @callback delete(cache_name :: atom, key :: atom | String.t(), opts :: Keyword.t()) ::
              :ok | ErrorMessage.t()
  @callback delete(cache_name :: atom, key :: atom | String.t()) :: :ok | ErrorMessage.t()

  defmacro __using__(opts) do
    quote do
      opts = unquote(opts)

      @cache_opts opts
      @cache_name opts[:name]
      @cache_adapter if opts[:sandbox?], do: Cache.Sandbox, else: opts[:adapter]

      if !opts[:adapter] do
        raise "Must supply a cache adapter for #{__MODULE__}"
      end

      if !@cache_name do
        raise "Must supply a cache name for #{__MODULE__}"
      end

      pre_check_runtime_options = fn
        {_, _, _} = mfa ->
          mfa

        {_, _} = app_config ->
          app_config

        fun when is_function(fun, 0) ->
          fun

        app_name when is_atom(app_name) and not is_nil(app_name) ->
          app_name

        val ->
          raise ArgumentError, """
          Bad option in adapter module #{inspect(__MODULE__)}!

          Expected one of the following:

            * `{module, function, args}` - Module, function, args
            * `{application_name, key}` - Application name. This is called as `Application.fetch_env!(application_name, key)`.
            * `application_name` - Application name as an atom. This is called as `Application.fetch_env!(application_name, #{inspect(__MODULE__)})`.
            * `function` - Zero arity callback function. For eg. `&YourModule.options/0`
            * `[key: value_type]` - Keyword list of options.

          Got: #{inspect(val)}
          """
      end

      check_adapter_opts = fn
        adapter_opts when is_list(adapter_opts) ->
          NimbleOptions.validate!(adapter_opts, @cache_adapter.opts_definition())

        adapter_opts ->
          pre_check_runtime_options.(adapter_opts)

      end

      adapter_opts = if opts[:sandbox?], do: [], else: check_adapter_opts.(opts[:opts])

      @adapter_opts adapter_opts
      @compression_level if is_list(@adapter_opts), do: @adapter_opts[:compression_level]

      if macro_exported?(unquote(opts[:adapter]), :__using__, 1) do
        use unquote(opts[:adapter])
      end

      def cache_name, do: @cache_name
      def cache_adapter, do: @cache_adapter

      def adapter_options, do: adapter_options!(@adapter_opts)

      defp adapter_options!({module, fun, args}), do: apply(module, fun, args)
      defp adapter_options!({app, key}), do: Application.fetch_env!(app, key)
      defp adapter_options!(app_name) when is_atom(app_name), do: Application.fetch_env!(app_name, __MODULE__)
      defp adapter_options!(fun) when is_function(fun, 0), do: fun.()
      defp adapter_options!(options), do: options

      def child_spec(_) do
        @cache_adapter.child_spec({@cache_name, adapter_options()})
      end

      def put(key, ttl \\ nil, value) do
        value = Cache.TermEncoder.encode(value, @compression_level)
        key = maybe_sandbox_key(key)

        :telemetry.span(
          [:elixir_cache, :cache, :put],
          %{cache_name: @cache_name},
          fn ->
            result = with {:error, error} = e <- @cache_adapter.put(@cache_name, key, ttl, value, adapter_options()) do
              :telemetry.execute([:elixir_cache, :cache, :put, :error], %{count: 1}, %{
                cache_name: @cache_name,
                error: error
              })

              e
            end

            {result, %{cache_name: @cache_name}}
          end
        )
      end

      def get(key) do
        key = maybe_sandbox_key(key)

        :telemetry.span(
          [:elixir_cache, :cache, :get],
          %{cache_name: @cache_name},
          fn ->
            result =
              case @cache_adapter.get(@cache_name, key, adapter_options()) do
                {:ok, nil} = res ->
                  :telemetry.execute([:elixir_cache, :cache, :get, :miss], %{count: 1}, %{
                    cache_name: @cache_name
                  })

                  res

                {:ok, value} -> {:ok, Cache.TermEncoder.decode(value)}

                {:error, error} = e ->
                  :telemetry.execute([:elixir_cache, :cache, :get, :error], %{count: 1}, %{
                    cache_name: @cache_name,
                    error: error
                  })

                  e
              end

            {result, %{cache_name: @cache_name}}
          end
        )
      end

      def delete(key) do
        key = maybe_sandbox_key(key)

        :telemetry.span(
          [:elixir_cache, :cache, :delete],
          %{cache_name: @cache_name},
          fn ->
            result = with {:error, error} = e <- @cache_adapter.delete(@cache_name, key, adapter_options()) do
              :telemetry.execute([:elixir_cache, :cache, :delete, :error], %{count: 1}, %{
                cache_name: @cache_name,
                error: error
              })

              e
            end

            {result, %{cache_name: @cache_name}}
          end
        )
      end

      def get_or_create(key, fnc) do
        Cache.get_or_create(__MODULE__, key, fnc)
      end

      if @cache_opts[:sandbox?] do
        defp maybe_sandbox_key(key) do
          sandbox_id = Cache.SandboxRegistry.find!(__MODULE__)

          "#{sandbox_id}:#{key}"
        end
      else
        defp maybe_sandbox_key(key) do
          key
        end
      end
    end
  end

  def child_spec(children) do
    %{
      id: Cache,
      type: :supervisor,
      start: {Cache, :start_link, [children]}
    }
  end

  def start_link(cache_children, opts \\ []) do
    Supervisor.start_link(Cache, cache_children, opts)
  end

  def init(cache_children) do
    Supervisor.init(cache_children, strategy: :one_for_one)
  end

  @doc """
  Retrieves a value from the cache if it exists, or executes a function to create and store it.  
  
  This is a convenience function implementing the common "get or create" pattern for caches. 
  It attempts to fetch a value from the cache first, and only if the value doesn't exist, 
  it will execute the provided function to generate the value and store it in the cache.
  
  ## Parameters
  
  - `cache` - The cache module to use (must implement the Cache behaviour)
  - `key` - The key to look up or create
  - `fnc` - A function that returns `{:ok, value}` or `{:error, reason}`
  
  ## Returns
  
  - `{:ok, value}` - The value from cache or newly created value
  - `{:error, reason}` - If an error occurred during retrieval or creation
  
  ## Examples
  
  ```elixir
  Cache.get_or_create(MyApp.Cache, "user:123", fn ->
    case UserRepo.get(123) do
      nil -> {:error, ErrorMessage.not_found("User not found")}
      user -> {:ok, user}
    end
  end)
  ```
  """
  @spec get_or_create(module(), atom() | String.t(), (-> {:ok, any()} | {:error, any()})) :: 
          {:ok, any()} | {:error, any()}
  def get_or_create(cache, key, fnc) do
    case cache.get(key) do
      {:ok, nil} ->
        with {:ok, value} <- fnc.(),
             :ok <- cache.put(key, value) do
          {:ok, value}
        end

      {:ok, _} = res -> res

      {:error, _} = e -> e
    end
  end
end
