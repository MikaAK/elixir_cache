defmodule Cache.RedisSandboxTest do
  @moduledoc """
  Sandbox coverage for the Redis-only surface `use Cache, adapter: Cache.Redis`
  injects (set ops, raw command/pipeline). These run against `Cache.Sandbox`,
  so no Redis is needed.
  """
  use ExUnit.Case, async: true

  defmodule RedisSandboxCache do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis_sandbox,
      opts: [uri: "redis://localhost:6379"],
      sandbox?: true
  end

  setup do
    Cache.SandboxRegistry.start(RedisSandboxCache)

    :ok
  end

  describe "&sadd/3 and &smembers/2" do
    test "smembers of a missing key is an empty list" do
      assert {:ok, []} === RedisSandboxCache.smembers("missing", [])
    end

    test "sadd returns the number of newly added members and smembers returns the set" do
      assert {:ok, 1} === RedisSandboxCache.sadd("symbols", "AAPL")
      assert {:ok, 1} === RedisSandboxCache.sadd("symbols", "TSLA")
      assert {:ok, 0} === RedisSandboxCache.sadd("symbols", "AAPL")

      assert {:ok, members} = RedisSandboxCache.smembers("symbols", [])
      assert ["AAPL", "TSLA"] === Enum.sort(members)
    end

    test "members round-trip as terms, not binaries" do
      assert {:ok, 1} === RedisSandboxCache.sadd("terms", %{symbol: "AAPL", strike: 150.0})
      assert {:ok, [%{symbol: "AAPL", strike: 150.0}]} === RedisSandboxCache.smembers("terms", [])
    end

    test "sets are isolated per sandbox" do
      assert {:ok, []} === RedisSandboxCache.smembers("symbols", [])
    end
  end

  describe "&command/2" do
    test "PING" do
      assert {:ok, "PONG"} === RedisSandboxCache.command(["PING"])
    end

    test "GET / EXISTS / DEL against keys written through the cache API" do
      assert :ok === RedisSandboxCache.put("key", "value")

      # Raw GET returns the stored binary undecoded, exactly like Redis would —
      # the Redis-backed sandbox term-encodes on put to round-trip faithfully.
      assert {:ok, encoded} = RedisSandboxCache.command(["GET", "key"])
      assert "value" === Cache.TermEncoder.decode(encoded)
      assert {:ok, 1} === RedisSandboxCache.command(["EXISTS", "key"])
      assert {:ok, 1} === RedisSandboxCache.command(["DEL", "key"])
      assert {:ok, nil} === RedisSandboxCache.command(["GET", "key"])
      assert {:ok, 0} === RedisSandboxCache.command(["EXISTS", "key"])
      assert {:ok, 0} === RedisSandboxCache.command(["DEL", "key"])
    end

    test "unsupported commands return a not-implemented error instead of raising" do
      assert {:error, %ErrorMessage{code: :not_implemented, details: %{command: "ZADD"}}} =
               RedisSandboxCache.command(["ZADD", "key", "1", "member"])
    end
  end

  describe "&pipeline/2" do
    test "runs each command in order and returns the replies as a list" do
      assert :ok === RedisSandboxCache.put("key", "value")

      assert {:ok, ["PONG", encoded, 1]} =
               RedisSandboxCache.pipeline([["PING"], ["GET", "key"], ["DEL", "key"]])

      assert "value" === Cache.TermEncoder.decode(encoded)
    end

    test "an unsupported command fails the whole pipeline" do
      assert {:error, %ErrorMessage{code: :not_implemented}} =
               RedisSandboxCache.pipeline([["PING"], ["ZADD", "key", "1", "member"]])
    end
  end

  describe "&command!/2 and &pipeline!/2" do
    test "return the raw reply on success" do
      assert "PONG" === RedisSandboxCache.command!(["PING"])
      assert ["PONG", "PONG"] === RedisSandboxCache.pipeline!([["PING"], ["PING"]])
    end

    test "raise on an unsupported command" do
      assert_raise RuntimeError, ~r/not implemented/, fn ->
        RedisSandboxCache.command!(["ZADD", "key", "1", "member"])
      end

      assert_raise RuntimeError, ~r/not implemented/, fn ->
        RedisSandboxCache.pipeline!([["ZADD", "key", "1", "member"]])
      end
    end
  end
end
