defmodule Cache.TermEncoderTest do
  use ExUnit.Case, async: true

  alias Cache.TermEncoder

  describe "&encode/2" do
    test "encodes integers properly" do
      assert 1 === TermEncoder.encode(1, nil)
    end

    test "encodes a JSON string as a term rather than handing it through unencoded" do
      json = Jason.encode!(%{"a" => 1})
      encoded = TermEncoder.encode(json, nil)

      assert <<131, _rest::binary>> = encoded
      assert :erlang.binary_to_term(encoded) === json
    end

    test "encodes terms properly" do
      binary = TermEncoder.encode(%{term: 1}, 4)

      assert :erlang.binary_to_term(binary) === %{term: 1}
    end
  end

  describe "&decode/1" do
    test "decodes an unencoded integer written by an earlier version" do
      assert 123 === TermEncoder.decode("123")
    end

    test "decodes an unencoded JSON string written by an earlier version" do
      json = Jason.encode!(%{"a" => 1})

      assert %{"a" => 1} === TermEncoder.decode(json)
    end

    test "decodes terms properly" do
      term = %{test: 1}
      binary = :erlang.term_to_binary(term)

      assert TermEncoder.decode(binary) === term
    end
  end
end
