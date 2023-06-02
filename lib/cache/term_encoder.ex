defmodule Cache.TermEncoder do
  @moduledoc false

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
        Jason.decode!(binary)

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
