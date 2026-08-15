defmodule Cache.NativeTermStorageTest do
  @moduledoc """
  Proves values are encoded only for adapters that actually need bytes.

  Adapters that store Erlang terms natively (ETS, Agent, PersistentTerm, ConCache)
  must hand the term straight to the store, and adapters that store bytes (Redis) or
  own a durable on-disk format (DETS, ETS with `:rehydration_path`) must keep encoding.
  """

  use ExUnit.Case, async: true

  defmodule ETSCache do
    use Cache, adapter: Cache.ETS, name: :nts_ets, opts: []
  end

  defmodule AgentCache do
    use Cache, adapter: Cache.Agent, name: :nts_agent, opts: []
  end

  defmodule PersistentTermCache do
    use Cache, adapter: Cache.PersistentTerm, name: :nts_persistent_term, opts: []
  end

  defmodule ConCacheCache do
    use Cache, adapter: Cache.ConCache, name: :nts_con_cache, opts: []
  end

  defmodule RedisCache do
    use Cache, adapter: Cache.Redis, name: :nts_redis, opts: [uri: "redis://localhost:6379"]
  end

  defmodule DETSCache do
    use Cache, adapter: Cache.DETS, name: :nts_dets, opts: [file_path: "/tmp/nts_dets"]
  end

  defstruct [:name, :count]

  @native_caches [ETSCache, AgentCache, PersistentTermCache, ConCacheCache]

  setup do
    start_supervised!({Cache, [ETSCache, AgentCache, PersistentTermCache, ConCacheCache, RedisCache, DETSCache]})

    :ok
  end

  describe "&Cache.TermEncoder.encoding_required?/2" do
    test "is false for adapters that store terms natively" do
      refute Cache.TermEncoder.encoding_required?(Cache.ETS, [])
      refute Cache.TermEncoder.encoding_required?(Cache.Agent, [])
      refute Cache.TermEncoder.encoding_required?(Cache.PersistentTerm, [])
      refute Cache.TermEncoder.encoding_required?(Cache.ConCache, [])
      refute Cache.TermEncoder.encoding_required?(Cache.Counter, [])
    end

    test "is true for adapters that store bytes or persist to disk" do
      assert Cache.TermEncoder.encoding_required?(Cache.Redis, [])
      assert Cache.TermEncoder.encoding_required?(Cache.DETS, [])
    end

    test "is true for a native adapter that persists its table to disk" do
      assert Cache.TermEncoder.encoding_required?(Cache.ETS, rehydration_path: "/tmp/nts")
    end

    test "is true when compression_level is set — the caller asked for compression" do
      assert Cache.TermEncoder.encoding_required?(Cache.ETS, compression_level: 6)
      assert Cache.TermEncoder.encoding_required?(Cache.Agent, compression_level: 1)
    end

    test "defaults to true for a third-party adapter that does not implement the callback" do
      defmodule ThirdPartyAdapter do
        @behaviour Cache

        @impl Cache
        def opts_definition, do: []
        @impl Cache
        def start_link(_opts), do: :ignore
        @impl Cache
        def child_spec({_name, _opts}), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
        @impl Cache
        def get(_name, _key, _opts \\ []), do: {:ok, nil}
        @impl Cache
        def put(_name, _key, _ttl \\ nil, _value, _opts \\ []), do: :ok
        @impl Cache
        def delete(_name, _key, _opts \\ []), do: :ok
      end

      assert Cache.TermEncoder.encoding_required?(ThirdPartyAdapter, [])
    end

    test "is true when opts are resolved at runtime and cannot be read at compile time" do
      assert Cache.TermEncoder.encoding_required?(Cache.ETS, {:my_app, :some_key})
      assert Cache.TermEncoder.encoding_required?(Cache.ETS, {MyMod, :opts, []})
    end

    test "a strategy delegates to the adapter it wraps" do
      refute Cache.TermEncoder.encoding_required?({Cache.RefreshAhead, Cache.ETS}, [])
      assert Cache.TermEncoder.encoding_required?({Cache.RefreshAhead, Cache.Redis}, [])
    end

    test "is true for a strategy that hands the stored value to another node" do
      assert Cache.TermEncoder.encoding_required?({Cache.HashRing, Cache.ETS}, [])

      assert Cache.TermEncoder.encoding_required?(
               {Cache.MultiLayer, [ETSCache]},
               broadcast_mode: :replicate
             )
    end

    test "is false for a MultiLayer that keeps values node-local" do
      refute Cache.TermEncoder.encoding_required?({Cache.MultiLayer, [ETSCache]}, [])

      refute Cache.TermEncoder.encoding_required?(
               {Cache.MultiLayer, [ETSCache]},
               broadcast_mode: :invalidate
             )
    end
  end

  describe "native adapters store the raw term" do
    test "the value in the underlying store is the term itself, not a binary" do
      value = %{user: "mika", roles: [:admin]}

      for cache <- @native_caches do
        assert :ok === cache.put(:raw_key, value)
      end

      assert [{:raw_key, ^value}] = :ets.lookup(:nts_ets, :raw_key)
      assert %{raw_key: ^value} = Agent.get(:nts_agent, & &1)
      assert ^value = :persistent_term.get({:nts_persistent_term, :raw_key})
      assert ^value = ConCache.get(:nts_con_cache, :raw_key)
    end

    test "arbitrary terms round-trip identically without encoding" do
      terms = [
        %{nested: %{list: [1, 2, 3]}},
        {:tuple, "with", 3, :parts},
        %__MODULE__{name: "struct", count: 7},
        [keyword: :list, another: 1],
        self(),
        :an_atom,
        "a plain string",
        123,
        1.5,
        nil,
        <<1, 2, 3>>
      ]

      for cache <- @native_caches, term <- terms do
        assert :ok === cache.put(:round_trip, term)
        assert {:ok, ^term} = cache.get(:round_trip)
      end
    end

    test "a pid round-trips as the same live pid, not a decoded copy" do
      assert :ok === ETSCache.put(:pid_key, self())
      assert {:ok, pid} = ETSCache.get(:pid_key)

      assert pid === self()
      assert Process.alive?(pid)
    end

    test "raw ETS operations see real terms, so match_object and tab2list work" do
      assert :ok === ETSCache.put(:mika, %{name: "mika"})

      assert [mika: %{name: "mika"}] === ETSCache.tab2list()
      assert [mika: %{name: "mika"}] === ETSCache.match_object({:_, %{name: "mika"}})
    end

    test "a ConCache get_or_store writes a value that get can read back" do
      assert "stored" === ConCacheCache.get_or_store(:gos_key, nil, fn -> "stored" end)
      assert {:ok, "stored"} === ConCacheCache.get(:gos_key)
    end

    test "a PersistentTerm read hands out the same term on every read, with no copy" do
      value = Enum.to_list(1..500)

      assert :ok === PersistentTermCache.put(:zero_copy, value)
      assert {:ok, first} = PersistentTermCache.get(:zero_copy)
      assert {:ok, second} = PersistentTermCache.get(:zero_copy)

      assert :erts_debug.same(first, second)
    end
  end

  describe "adapters that need bytes still encode" do
    test "a Redis value is stored as an encoded binary and decoded on read" do
      value = %{user: "mika", roles: [:admin]}

      assert :ok === RedisCache.put("encoded_key", value)

      raw = Cache.Redis.command!(:nts_redis, ["GET", "nts_redis:encoded_key"])

      assert is_binary(raw)
      assert :erlang.binary_to_term(raw) === value
      assert {:ok, ^value} = RedisCache.get("encoded_key")
    end

    test "a DETS value is stored as an encoded binary so existing on-disk files stay readable" do
      on_exit(fn -> File.rm_rf("/tmp/nts_dets") end)

      value = %{user: "mika"}

      assert :ok === DETSCache.put(:dets_key, value)
      assert [{:dets_key, raw}] = :dets.lookup(:nts_dets, :dets_key)

      assert is_binary(raw)
      assert :erlang.binary_to_term(raw) === value
      assert {:ok, ^value} = DETSCache.get(:dets_key)
    end

    test "a Redis key written by an older version still decodes to the original term" do
      legacy = :erlang.term_to_binary(%{written_by: "0.4.9"})
      Cache.Redis.command!(:nts_redis, ["SET", "nts_redis:legacy_key", legacy])

      assert {:ok, %{written_by: "0.4.9"}} === RedisCache.get("legacy_key")
    end

    test "a DETS file written by an older version still decodes to the original term" do
      on_exit(fn -> File.rm_rf("/tmp/nts_dets") end)

      legacy = :erlang.term_to_binary(%{written_by: "0.4.9"})
      :dets.insert(:nts_dets, {:legacy_key, legacy})

      assert {:ok, %{written_by: "0.4.9"}} === DETSCache.get(:legacy_key)
    end

    test "an explicit compression_level still compresses on a native adapter" do
      value = String.duplicate("compress me ", 500)
      opts = [compression_level: 6]

      encoded = Cache.TermEncoder.maybe_encode(value, Cache.ETS, opts)

      assert is_binary(encoded)
      assert byte_size(encoded) < byte_size(:erlang.term_to_binary(value))
      assert Cache.TermEncoder.maybe_decode(encoded, Cache.ETS, opts) === value
    end
  end

  describe "the durability invariant" do
    test "every store whose data outlives the process that wrote it still encodes" do
      # This is the whole upgrade-safety argument in one assertion. Skipping the encode
      # is only safe where the previous version's bytes cannot survive to be read by
      # this one, which means the value dies with the VM that wrote it. Anything that
      # reaches a disk, a Redis server or another node keeps the 0.4.x representation.
      # A new adapter or option that persists values belongs in this list on the day it
      # lands, not after an upgrade hands somebody a raw `<<131, ...>>` binary.
      durable_stores = [
        {Cache.Redis, [uri: "redis://localhost:6379"]},
        {Cache.DETS, [file_path: "/tmp/nts_dets"]},
        {Cache.ETS, [rehydration_path: "/tmp/nts"]},
        {{Cache.HashRing, Cache.ETS}, []},
        {{Cache.MultiLayer, [ETSCache]}, [broadcast_mode: :replicate]}
      ]

      Enum.each(durable_stores, fn {adapter, opts} ->
        assert Cache.TermEncoder.encoding_required?(adapter, opts),
               "#{inspect(adapter)} keeps values past the process that wrote them, so it must " <>
                 "encode — otherwise an upgrade reads the previous version's bytes as a term"
      end)
    end

    test "every store that does not encode loses its data when the VM stops" do
      volatile_stores = [Cache.ETS, Cache.Agent, Cache.PersistentTerm, Cache.ConCache, Cache.Counter]

      Enum.each(volatile_stores, fn adapter ->
        refute Cache.TermEncoder.encoding_required?(adapter, []),
               "#{inspect(adapter)} holds terms in memory only, so encoding them buys nothing"
      end)
    end
  end

  describe "binaries that look like JSON" do
    test "a brace-wrapped string round-trips unchanged on a native adapter" do
      assert :ok === ETSCache.put(:json_ish, ~s({"a": 1}))

      assert {:ok, ~s({"a": 1})} === ETSCache.get(:json_ish)
    end

    test "a brace-wrapped string that is not valid JSON no longer raises on read" do
      assert :ok === RedisCache.put("not_json", "{oops not json}")

      assert {:ok, "{oops not json}"} === RedisCache.get("not_json")
    end
  end
end
