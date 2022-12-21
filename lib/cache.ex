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

      adapter_opts = if opts[:sandbox?], do: [], else: opts[:opts]

      @adapter_opts NimbleOptions.validate!(adapter_opts, @cache_adapter.opts_definition())
      @compression_level @adapter_opts[:compression_level]

      if macro_exported?(unquote(opts[:adapter]), :__using__, 1) do
        use unquote(opts[:adapter])
      end

      def cache_name, do: @cache_name
      def cache_adapter, do: @cache_adapter

      def child_spec(_) do
        @cache_adapter.child_spec({@cache_name, @adapter_opts})
      end

      def put(key, ttl \\ nil, value) do
        value = Cache.TermEncoder.encode(value, @compression_level)
        key = maybe_sandbox_key(key)

        @cache_adapter.put(@cache_name, key, ttl, value, @adapter_opts)
      end

      def get(key) do
        key = maybe_sandbox_key(key)

        with {:ok, value} when not is_nil(value) <-
               @cache_adapter.get(@cache_name, key, @adapter_opts) do
          {:ok, Cache.TermEncoder.decode(value)}
        end
      end

      def delete(key) do
        key = maybe_sandbox_key(key)

        @cache_adapter.delete(@cache_name, key, @adapter_opts)
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
