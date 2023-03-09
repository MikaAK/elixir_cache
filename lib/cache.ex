defmodule Cache do
  @moduledoc "#{File.read!("./README.md")}"

  use Supervisor

  @callback child_spec({
              cache_name :: atom,
              cache_opts :: Keyword.t()
            }) :: Supervisor.child_spec() | :supervisor.child_spec()

  @callback opts_definition() :: Keyword.t()

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
      defp adapter_options!(options) when is_list(options), do: options

      def child_spec(_) do
        @cache_adapter.child_spec({@cache_name, adapter_options()})
      end

      def put(key, ttl \\ nil, value) do
        value = Cache.TermEncoder.encode(value, @compression_level)
        key = maybe_sandbox_key(key)

        @cache_adapter.put(@cache_name, key, ttl, value, adapter_options())
      end

      def get(key) do
        key = maybe_sandbox_key(key)

        with {:ok, value} when not is_nil(value) <-
               @cache_adapter.get(@cache_name, key, adapter_options()) do
          {:ok, Cache.TermEncoder.decode(value)}
        end
      end

      def delete(key) do
        key = maybe_sandbox_key(key)

        @cache_adapter.delete(@cache_name, key, adapter_options())
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

  def start_link(cache_children, opts \\ []) do
    Supervisor.start_link(Cache, cache_children, opts)
  end

  def init(cache_children) do
    Supervisor.init(cache_children, strategy: :one_for_one)
  end
end
