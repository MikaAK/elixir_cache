defmodule Cache.ETSSandboxTest do
  use ExUnit.Case, async: true

  defmodule TestETSSandboxCache do
    use Cache,
      adapter: Cache.ETS,
      name: :test_ets_sandbox_cache,
      opts: [],
      sandbox?: Mix.env() === :test
  end

  setup do
    Cache.SandboxRegistry.start(TestETSSandboxCache)

    :ok
  end

  describe "update_counter/2 sandbox isolation" do
    test "update_counter works through sandbox adapter" do
      TestETSSandboxCache.put("counter_key", 0)

      result = TestETSSandboxCache.update_counter("counter_key", 1)
      assert result === 1

      result = TestETSSandboxCache.update_counter("counter_key", 5)
      assert result === 6
    end

    test "update_counter is isolated between tests" do
      assert {:ok, nil} = TestETSSandboxCache.get("counter_key")
    end
  end

  describe "update_counter/3 sandbox isolation" do
    test "update_counter with default works through sandbox adapter" do
      result = TestETSSandboxCache.update_counter("new_counter", 1, {"new_counter", 10})
      assert result === 11
    end

    test "update_counter with default is isolated between tests" do
      assert {:ok, nil} = TestETSSandboxCache.get("new_counter")
    end
  end

  describe "insert_raw/1 sandbox isolation" do
    test "insert_raw with tuple works through sandbox adapter" do
      assert true = TestETSSandboxCache.insert_raw({"raw_key", "raw_value"})

      result = TestETSSandboxCache.match_object({:_, "raw_value"})
      assert length(result) === 1
    end

    test "insert_raw with list works through sandbox adapter" do
      assert true = TestETSSandboxCache.insert_raw([{"list_key1", "val1"}, {"list_key2", "val2"}])

      result = TestETSSandboxCache.match_object({:_, "val1"})
      assert length(result) === 1

      result = TestETSSandboxCache.match_object({:_, "val2"})
      assert length(result) === 1
    end

    test "insert_raw is isolated between tests" do
      assert [] = TestETSSandboxCache.match_object({:_, "raw_value"})
      assert [] = TestETSSandboxCache.match_object({:_, "val1"})
    end
  end

  describe "match_object/1 sandbox isolation" do
    test "match_object works through sandbox adapter" do
      TestETSSandboxCache.insert_raw({"mo_key1", "value1"})
      TestETSSandboxCache.insert_raw({"mo_key2", "value2"})

      result = TestETSSandboxCache.match_object({:_, "value1"})
      assert length(result) === 1
    end

    test "match_object is isolated between tests" do
      result = TestETSSandboxCache.match_object({:_, "value1"})
      assert result === []
    end
  end

  describe "match_object/2 sandbox isolation" do
    test "match_object with limit works through sandbox adapter" do
      TestETSSandboxCache.insert_raw({"mol_key1", "same_value"})
      TestETSSandboxCache.insert_raw({"mol_key2", "same_value"})
      TestETSSandboxCache.insert_raw({"mol_key3", "same_value"})

      {result, :end_of_table} = TestETSSandboxCache.match_object({:_, "same_value"}, 2)
      assert length(result) === 2
    end

    test "match_object with limit is isolated between tests" do
      result = TestETSSandboxCache.match_object({:_, "same_value"})
      assert result === []
    end
  end
end
