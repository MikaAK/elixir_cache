defmodule Cache.CompressionLevelTest do
  @moduledoc """
  `:compression_level` was unreachable on every path: no adapter declares it, so
  `NimbleOptions` rejected it on compile-time opts, and it never reached the encoder
  on any other. These tests hold it reachable.
  """

  use ExUnit.Case, async: true

  @value String.duplicate("compress me ", 500)

  defmodule CompressedCache do
    use Cache, adapter: Cache.ETS, name: :compression_use_option, compression_level: 6, opts: []
  end

  defmodule AdapterOptsCache do
    use Cache, adapter: Cache.ETS, name: :compression_adapter_opts, opts: [compression_level: 6]
  end

  defmodule RedisCompressedCache do
    use Cache,
      adapter: Cache.Redis,
      name: :compression_redis,
      compression_level: 6,
      opts: [uri: "redis://localhost:6379"]
  end

  defmodule UncompressedCache do
    use Cache, adapter: Cache.ETS, name: :compression_none, opts: []
  end

  setup do
    start_supervised!(
      {Cache, [CompressedCache, AdapterOptsCache, RedisCompressedCache, UncompressedCache]}
    )

    :ok
  end

  describe "&put/3 with a compression level" do
    test "compresses the stored value and reads it back unchanged" do
      assert :ok === CompressedCache.put(:compressed, @value)
      assert [{:compressed, stored}] = :ets.lookup(:compression_use_option, :compressed)

      assert is_binary(stored)
      assert byte_size(stored) < byte_size(:erlang.term_to_binary(@value))
      assert {:ok, @value} === CompressedCache.get(:compressed)
    end

    test "reaches the encoder from the adapter opts as well" do
      assert :ok === AdapterOptsCache.put(:compressed, @value)
      assert [{:compressed, stored}] = :ets.lookup(:compression_adapter_opts, :compressed)

      assert byte_size(stored) < byte_size(:erlang.term_to_binary(@value))
      assert {:ok, @value} === AdapterOptsCache.get(:compressed)
    end

    test "compresses on an adapter that stores bytes" do
      assert :ok === RedisCompressedCache.put("compressed", @value)
      stored = Cache.Redis.command!(:compression_redis, ["GET", "compression_redis:compressed"])

      assert byte_size(stored) < byte_size(:erlang.term_to_binary(@value))
      assert {:ok, @value} === RedisCompressedCache.get("compressed")
    end

    test "an adapter that holds terms stores the term itself without one" do
      assert :ok === UncompressedCache.put(:plain, @value)
      assert [{:plain, stored}] = :ets.lookup(:compression_none, :plain)

      assert stored === @value
      assert {:ok, @value} === UncompressedCache.get(:plain)
    end
  end

  describe "&__using__/1 with a strategy adapter" do
    test "refuses a compression level rather than ignoring it" do
      assert_raise ArgumentError, ~r/not supported on a cache using a strategy adapter/, fn ->
        defmodule StrategyCompressedCache do
          use Cache,
            adapter: {Cache.HashRing, Cache.ETS},
            name: :compression_strategy,
            compression_level: 6,
            opts: []
        end
      end
    end
  end
end
