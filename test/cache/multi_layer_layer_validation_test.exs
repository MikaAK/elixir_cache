defmodule Cache.MultiLayerLayerValidationTest do
  @moduledoc """
  `Cache.MultiLayer` layers are `use Cache` MODULES. Anything else is rejected
  at startup by `validate_layers!/2`.

  The moduledoc previously documented three other forms — a bare adapter, a
  `{Adapter, opts}` tuple, and `__MODULE__` — and none of them worked. The
  adapter forms were the dangerous ones: dispatch gated on
  `function_exported?(module, :get, 1)`, which an adapter cannot satisfy
  (adapters export `get/3`), and the else branches returned `{:ok, nil}` and
  `:ok`.

  Those are SUCCESS shapes, which is what made the defect survive. A layer
  that always misses is indistinguishable from a cold cache; a write that
  no-ops is indistinguishable from one that worked. Every test asserting only
  "the cascade returns the right value" passes with the fast layer entirely
  inert — which is why the first suite written against this cascade passed
  while one of its two layers did nothing at all.

  So there are two things to pin, and both are about failure being visible:
  a bad layer is REJECTED LOUDLY at startup, and a good cascade is provably
  two layers rather than one.
  """
  use ExUnit.Case, async: true

  defmodule FastLayer do
    @moduledoc false
    use Cache, adapter: Cache.ETS, name: :multi_layer_validation_fast, opts: []
  end

  defmodule SlowLayer do
    @moduledoc false
    use Cache, adapter: Cache.ETS, name: :multi_layer_validation_slow, opts: []
  end

  defmodule LayeredCache do
    @moduledoc false
    use Cache,
      adapter: {Cache.MultiLayer, [FastLayer, SlowLayer]},
      name: :multi_layer_validation_cascade,
      opts: [backfill_ttl: :timer.seconds(60)]
  end

  describe "layer validation rejects non-modules at startup" do
    test "a bare adapter raises, naming the offending element" do
      assert_raise ArgumentError, ~r/must be a `use Cache` module/, fn ->
        Cache.MultiLayer.child_spec({:rejects_adapter, [Cache.ETS, SlowLayer], []})
      end
    end

    test "the message names the adapter that was passed" do
      error =
        assert_raise ArgumentError, fn ->
          Cache.MultiLayer.child_spec({:rejects_adapter_named, [Cache.ETS], []})
        end

      assert error.message =~ "Cache.ETS"
      assert error.message =~ "Wrap it in a module"
    end

    test "an {Adapter, opts} tuple raises rather than crashing on a missing clause" do
      assert_raise ArgumentError, ~r/must be a `use Cache` module/, fn ->
        Cache.MultiLayer.child_spec({:rejects_tuple, [{Cache.ETS, []}, SlowLayer], []})
      end
    end

    test "an unloaded or misspelled module raises" do
      assert_raise ArgumentError, ~r/must be a `use Cache` module/, fn ->
        Cache.MultiLayer.child_spec({:rejects_typo, [NoSuchCacheModule], []})
      end
    end

    test "POSITIVE CONTROL: a list of real cache modules is accepted" do
      assert %{id: _id, start: _start} =
               Cache.MultiLayer.child_spec({:accepts_modules, [FastLayer, SlowLayer], []})
    end
  end

  describe "a validated cascade is actually two layers" do
    setup do
      start_supervised!({Cache, [FastLayer, SlowLayer, LayeredCache]})
      :ok
    end

    # The only assertion a broken fast layer cannot fake: write to the SLOW
    # layer only, then remove it. Nothing but a real backfill into a real fast
    # layer can answer the second read.
    test "a slow-layer hit backfills the fast layer, and survives the slow copy going away" do
      :ok = SlowLayer.put("k", nil, "slow_only")

      assert {:ok, "slow_only"} = LayeredCache.get("k")

      :ok = SlowLayer.delete("k")
      assert {:ok, nil} = SlowLayer.get("k")

      assert {:ok, "slow_only"} = LayeredCache.get("k")
    end

    test "a write reaches the fast layer, not only the slow one" do
      :ok = LayeredCache.put("w", nil, "written")

      :ok = SlowLayer.delete("w")
      assert {:ok, nil} = SlowLayer.get("w")

      assert {:ok, "written"} = LayeredCache.get("w")
    end

    test "a write reaches the slow layer, not only the fast one" do
      :ok = LayeredCache.put("s", nil, "written")

      assert {:ok, "written"} = SlowLayer.get("s")
    end

    test "delete clears both layers" do
      :ok = LayeredCache.put("d", nil, "gone")
      :ok = LayeredCache.delete("d")

      assert {:ok, nil} = FastLayer.get("d")
      assert {:ok, nil} = SlowLayer.get("d")
      assert {:ok, nil} = LayeredCache.get("d")
    end
  end
end
