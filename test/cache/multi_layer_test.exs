defmodule Cache.MultiLayerTest do
  use ExUnit.Case, async: true

  defmodule FastCache do
    use Cache,
      adapter: Cache.ETS,
      name: :ml_fast_cache,
      opts: []
  end

  defmodule SlowCache do
    use Cache,
      adapter: Cache.ETS,
      name: :ml_slow_cache,
      opts: []
  end

  defmodule TwoLayerCache do
    use Cache,
      adapter: {Cache.MultiLayer, [FastCache, SlowCache]},
      name: :two_layer_cache,
      opts: []
  end

  defmodule FetchCache do
    use Cache,
      adapter: {Cache.MultiLayer, [FastCache, SlowCache]},
      name: :fetch_cache,
      opts: [on_fetch: &__MODULE__.fetch/1]

    def fetch(key), do: {:ok, "fetched:#{key}"}
  end

  defmodule BackfillTtlCache do
    use Cache,
      adapter: {Cache.MultiLayer, [FastCache, SlowCache]},
      name: :backfill_ttl_cache,
      opts: [backfill_ttl: 5000]
  end

  setup do
    start_supervised!(%{
      id: :fast_cache_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[FastCache, SlowCache], [name: :fast_slow_sup]]}
    })

    start_supervised!(%{
      id: :two_layer_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[TwoLayerCache], [name: :two_layer_sup]]}
    })

    start_supervised!(%{
      id: :fetch_cache_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[FetchCache], [name: :fetch_cache_sup]]}
    })

    start_supervised!(%{
      id: :backfill_ttl_sup,
      type: :supervisor,
      start: {Cache, :start_link, [[BackfillTtlCache], [name: :backfill_ttl_sup]]}
    })

    :ok
  end

  describe "put/3 writes slowest to fastest" do
    test "value is available in both layers after put" do
      assert :ok === TwoLayerCache.put("write_key", "write_value")

      assert {:ok, "write_value"} === FastCache.get("write_key")
      assert {:ok, "write_value"} === SlowCache.get("write_key")
    end

    test "overwrites existing values in all layers" do
      assert :ok === TwoLayerCache.put("overwrite_key", "first")
      assert :ok === TwoLayerCache.put("overwrite_key", "second")

      assert {:ok, "second"} === FastCache.get("overwrite_key")
      assert {:ok, "second"} === SlowCache.get("overwrite_key")
    end
  end

  describe "get/1 reads fastest to slowest" do
    test "returns value from fast layer when present" do
      FastCache.put("fast_only", "from_fast")
      SlowCache.put("fast_only", "from_slow")

      assert {:ok, "from_fast"} === TwoLayerCache.get("fast_only")
    end

    test "returns value from slow layer when fast layer misses" do
      SlowCache.put("slow_only", "from_slow")

      assert {:ok, "from_slow"} === TwoLayerCache.get("slow_only")
    end

    test "returns nil when all layers miss" do
      assert {:ok, nil} === TwoLayerCache.get("totally_missing")
    end
  end

  describe "get/1 backfills faster layers on slow-layer hit" do
    test "backfills fast layer when value found in slow layer" do
      SlowCache.put("backfill_key", "backfill_value")

      assert {:ok, nil} === FastCache.get("backfill_key")

      assert {:ok, "backfill_value"} === TwoLayerCache.get("backfill_key")

      assert {:ok, "backfill_value"} === FastCache.get("backfill_key")
    end
  end

  describe "delete/1 removes from all layers" do
    test "deletes from all layers" do
      assert :ok === TwoLayerCache.put("delete_key", "to_delete")

      assert {:ok, "to_delete"} === TwoLayerCache.get("delete_key")

      assert :ok === TwoLayerCache.delete("delete_key")

      assert {:ok, nil} === TwoLayerCache.get("delete_key")
    end
  end

  describe "on_fetch callback" do
    test "calls fetch callback on total miss" do
      assert {:ok, "fetched:missing_key"} === FetchCache.get("missing_key")
    end

    test "backfills all layers after fetch" do
      FetchCache.get("fetch_backfill_key")

      assert {:ok, "fetched:fetch_backfill_key"} === FastCache.get("fetch_backfill_key")
      assert {:ok, "fetched:fetch_backfill_key"} === SlowCache.get("fetch_backfill_key")
    end

    test "does not call fetch when value exists" do
      FastCache.put("existing_key", "existing_value")

      assert {:ok, "existing_value"} === FetchCache.get("existing_key")
    end
  end

  describe "cache_adapter/0" do
    test "returns Cache.MultiLayer as adapter" do
      assert TwoLayerCache.cache_adapter() === Cache.MultiLayer
    end
  end

  describe "Cache.Strategy.strategy?/1" do
    test "recognises Cache.MultiLayer as a strategy" do
      assert Cache.Strategy.strategy?(Cache.MultiLayer) === true
    end
  end
end
