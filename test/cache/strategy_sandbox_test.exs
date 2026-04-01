defmodule Cache.StrategySandboxTest do
  use ExUnit.Case, async: true

  defmodule HashRingSandboxCache do
    use Cache,
      adapter: {Cache.HashRing, Cache.ETS},
      name: :test_hash_ring_sandbox_cache,
      opts: [],
      sandbox?: Mix.env() === :test
  end

  setup do
    Cache.SandboxRegistry.start(HashRingSandboxCache)

    :ok
  end

  describe "HashRing + sandbox" do
    test "adapter is swapped to Cache.Sandbox" do
      assert HashRingSandboxCache.cache_adapter() === Cache.Sandbox
    end

    test "put and get work through sandbox" do
      assert :ok = HashRingSandboxCache.put("key1", "value1")
      assert {:ok, "value1"} = HashRingSandboxCache.get("key1")
    end

    test "delete works through sandbox" do
      assert :ok = HashRingSandboxCache.put("del_key", "del_val")
      assert {:ok, "del_val"} = HashRingSandboxCache.get("del_key")
      assert :ok = HashRingSandboxCache.delete("del_key")
      assert {:ok, nil} = HashRingSandboxCache.get("del_key")
    end

    test "data is isolated between tests" do
      assert {:ok, nil} = HashRingSandboxCache.get("key1")
      assert {:ok, nil} = HashRingSandboxCache.get("del_key")
    end
  end
end
