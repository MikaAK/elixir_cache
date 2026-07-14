defmodule Cache.TermEncoder do
  @moduledoc false

  # SECTION ADAPTER CAPABILITY
  #
  # Adapters that store Erlang terms natively (ETS, Agent, PersistentTerm, ConCache,
  # Counter) do not need `term_to_binary/1` — the round trip is pure overhead and it
  # is the dominant cost on a hot read path. Adapters that store bytes (Redis) or
  # that own a durable on-disk format (DETS) still need it.
  #
  # Resolution is done once at compile time by the `Cache` macro, so there is no
  # runtime branch on the read/write path.

  @doc """
  Returns true when values must be encoded to a binary before being handed to the adapter.

  Encoding is required when:

    * the adapter stores bytes rather than terms (`Cache.Redis`), or
    * the adapter persists an encoded format to disk (`Cache.DETS`,
      `Cache.ETS` with `:rehydration_path`), or
    * `:compression_level` is set — the caller explicitly asked for compression, or
    * the adapter opts are resolved at runtime, so the capability cannot be read at
      compile time. Encoding is the safe default: it is what every adapter did before.

  Third-party adapters that do not implement `c:Cache.native_term_storage?/1` keep
  encoding, so they are unaffected.
  """
  @spec encoding_required?(module() | {module(), term()}, keyword() | term()) :: boolean()
  def encoding_required?(adapter, adapter_opts)

  def encoding_required?(adapter, nil), do: encoding_required?(adapter, [])

  def encoding_required?(_adapter, adapter_opts) when not is_list(adapter_opts), do: true

  def encoding_required?(adapter, adapter_opts) do
    if is_nil(adapter_opts[:compression_level]) do
      not native_term_storage?(adapter, adapter_opts)
    else
      true
    end
  end

  @doc """
  Returns true when the adapter stores Erlang terms natively, given its options.

  Strategy adapters (`{Cache.HashRing, Cache.ETS}`) delegate to the adapter they wrap.
  """
  @spec native_term_storage?(module() | {module(), term()}, keyword()) :: boolean()
  def native_term_storage?(adapter, adapter_opts)

  def native_term_storage?({_strategy_module, underlying_adapter}, adapter_opts)
      when is_atom(underlying_adapter) do
    native_term_storage?(underlying_adapter, adapter_opts)
  end

  # Strategies configured with something other than an adapter module (eg the layer
  # list of `Cache.MultiLayer`) only reach this path under `sandbox?: true`, where the
  # store is `Cache.Sandbox` and holds terms natively.
  def native_term_storage?({_strategy_module, _strategy_config}, _adapter_opts), do: true

  def native_term_storage?(adapter, adapter_opts) when is_atom(adapter) do
    if function_exported?(adapter, :native_term_storage?, 1) do
      adapter.native_term_storage?(adapter_opts)
    else
      compile_time_native_term_storage?(adapter, adapter_opts)
    end
  end

  # `function_exported?/3` is false for a module that has not been loaded yet, which
  # happens when an adapter is compiled in the same project as the cache using it.
  # `Code.ensure_compiled/1` blocks on the parallel compiler so the answer is stable
  # across builds rather than depending on compilation order.
  defp compile_time_native_term_storage?(adapter, adapter_opts) do
    case Code.ensure_compiled(adapter) do
      {:module, module} ->
        function_exported?(module, :native_term_storage?, 1) and
          module.native_term_storage?(adapter_opts)

      {:error, _reason} ->
        false
    end
  end

  @doc """
  Encodes only when the adapter needs bytes. Used by strategy adapters, which resolve
  their underlying adapter at runtime rather than at compile time.
  """
  @spec maybe_encode(term(), module(), keyword()) :: term()
  def maybe_encode(term, adapter, adapter_opts) do
    if encoding_required?(adapter, adapter_opts) do
      encode(term, compression_level(adapter_opts))
    else
      term
    end
  end

  @doc """
  Decodes only when the adapter needs bytes. The inverse of `maybe_encode/3`.
  """
  @spec maybe_decode(term(), module(), keyword()) :: term()
  def maybe_decode(term, adapter, adapter_opts) do
    if encoding_required?(adapter, adapter_opts) do
      decode(term)
    else
      term
    end
  end

  defp compression_level(adapter_opts) when is_list(adapter_opts), do: adapter_opts[:compression_level]
  defp compression_level(_adapter_opts), do: nil

  # SECTION ENCODING

  def encode(term, compression_level)
      when not is_nil(compression_level) and compression_level >= 1 do
    :erlang.term_to_binary(term,
      compressed: compression_level
    )
  end

  def encode(term, _) when is_integer(term) do
    term
  end

  def encode(term, _) when is_binary(term) do
    if to_string(term) =~ ~r/^{.*}$/ do
      term
    else
      :erlang.term_to_binary(term)
    end
  end

  def encode(term, _compression_level) do
    :erlang.term_to_binary(term)
  end

  def decode(binary) when is_binary(binary) do
    cond do
      binary =~ ~r/^\d+$/ ->
        String.to_integer(binary)

      binary =~ ~r/^{.*}$/ ->
        decode_json(binary)

      true ->
        binary
        |> :erlang.binary_to_term()
        |> maybe_decode_binary_struct_error
    end
  end

  def decode(term) do
    term
  end

  defp maybe_decode_binary_struct_error(%struct{} = data) do
    struct(struct, Map.to_list(data))
  end

  defp maybe_decode_binary_struct_error(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&maybe_decode_binary_struct_error/1)
    |> List.to_tuple()
  end

  defp maybe_decode_binary_struct_error(list) when is_list(list) do
    Enum.map(list, &maybe_decode_binary_struct_error/1)
  end

  defp maybe_decode_binary_struct_error(value) do
    value
  end

  def decode_json(nil), do: nil

  def decode_json(json) do
    case Jason.decode(json) do
      {:ok, data} -> data
      {:error, _} -> json
    end
  end

  def encode_json(value) do
    Jason.encode!(value)
  end
end
