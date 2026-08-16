defmodule Cache.JsonStringRoundTripTest do
  @moduledoc """
  A binary was stored unencoded when it happened to look like JSON, and `decode/1` then
  had to guess what it was looking at — so caching a JSON string handed back a map.
  These tests hold the round trip type-stable while keeping values written by earlier
  versions readable.
  """

  use ExUnit.Case, async: true

  defmodule RedisCache do
    use Cache, adapter: Cache.Redis, name: :json_round_trip_redis, opts: [uri: "redis://localhost:6379"]
  end

  defmodule ETSCache do
    use Cache, adapter: Cache.ETS, name: :json_round_trip_ets, opts: []
  end

  setup do
    start_supervised!({Cache, [RedisCache, ETSCache]})

    :ok
  end

  describe "&put/3 of a binary that looks like something else" do
    test "a JSON object string comes back as the same string" do
      value = ~s({"user": "mika", "roles": ["admin"]})

      assert :ok === RedisCache.put("json_object", value)
      assert {:ok, value} === RedisCache.get("json_object")

      assert :ok === ETSCache.put(:json_object, value)
      assert {:ok, value} === ETSCache.get(:json_object)
    end

    test "a brace-wrapped string that is not JSON comes back unchanged" do
      assert :ok === RedisCache.put("not_json", "{oops not json}")
      assert {:ok, "{oops not json}"} === RedisCache.get("not_json")
    end

    test "a string of digits stays a string" do
      assert :ok === RedisCache.put("digits", "42")
      assert {:ok, "42"} === RedisCache.get("digits")
    end

    test "an integer stays an integer" do
      assert :ok === RedisCache.put("integer", 42)
      assert {:ok, 42} === RedisCache.get("integer")
    end

    test "a binary that starts with the external term format version byte survives" do
      value = <<131, 104, 2, "not really a term">>

      assert :ok === RedisCache.put("term_lookalike", value)
      assert {:ok, value} === RedisCache.get("term_lookalike")
    end

    test "the stored bytes are external term format, not the raw string" do
      assert :ok === RedisCache.put("stored_shape", ~s({"a": 1}))
      stored = Cache.Redis.command!(:json_round_trip_redis, ["GET", "json_round_trip_redis:stored_shape"])

      assert <<131, _rest::binary>> = stored
      assert :erlang.binary_to_term(stored) === ~s({"a": 1})
    end
  end

  describe "&Cache.TermEncoder.decode/1 of values written by an earlier version" do
    test "a raw JSON string still decodes to a map" do
      assert %{"a" => 1} === Cache.TermEncoder.decode(~s({"a": 1}))
    end

    test "a raw digit string still decodes to an integer" do
      assert 42 === Cache.TermEncoder.decode("42")
    end

    test "a raw string that is neither is returned unchanged" do
      assert "just a string" === Cache.TermEncoder.decode("just a string")
    end

    test "a key written by an earlier version reads back the way it always did" do
      Cache.Redis.command!(:json_round_trip_redis, [
        "SET",
        "json_round_trip_redis:legacy_json",
        ~s({"written_by": "0.4.9"})
      ])

      assert {:ok, %{"written_by" => "0.4.9"}} === RedisCache.get("legacy_json")
    end
  end
end
