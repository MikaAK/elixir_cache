defmodule Cache.CounterTest do
  use ExUnit.Case, async: true

  defmodule TestCounterCache do
    use Cache,
      adapter: Cache.Counter,
      name: :test_counter_cache,
      opts: [initial_size: 16]
  end

  setup do
    start_supervised({Cache, [TestCounterCache]})
    Process.sleep(50)
    :ok
  end

  describe "get/1" do
    test "returns nil for an unknown key" do
      assert {:ok, nil} === TestCounterCache.get(:unknown_key)
    end

    test "returns integer value after increment" do
      TestCounterCache.increment(:get_test_key)
      assert {:ok, 1} === TestCounterCache.get(:get_test_key)
    end
  end

  describe "put/2 as increment/decrement" do
    test "put with 1 increments the counter" do
      assert :ok === TestCounterCache.put(:put_inc_key, 1)
      assert {:ok, 1} === TestCounterCache.get(:put_inc_key)
      assert :ok === TestCounterCache.put(:put_inc_key, 1)
      assert {:ok, 2} === TestCounterCache.get(:put_inc_key)
    end

    test "put with -1 decrements the counter" do
      TestCounterCache.put(:put_dec_key, 1)
      TestCounterCache.put(:put_dec_key, 1)
      assert :ok === TestCounterCache.put(:put_dec_key, -1)
      assert {:ok, 1} === TestCounterCache.get(:put_dec_key)
    end

    test "put with 0 returns an error" do
      assert {:error, _} = TestCounterCache.put(:bad_key, 0)
    end

    test "put with 2 returns an error" do
      assert {:error, _} = TestCounterCache.put(:bad_key, 2)
    end

    test "put with a string returns an error" do
      assert {:error, _} = TestCounterCache.put(:bad_key, "up")
    end
  end

  describe "increment/1,2" do
    test "increments by 1 by default" do
      assert :ok === TestCounterCache.increment(:inc_key)
      assert {:ok, 1} === TestCounterCache.get(:inc_key)
    end

    test "increments by the given step" do
      assert :ok === TestCounterCache.increment(:inc_step_key, 5)
      assert {:ok, 5} === TestCounterCache.get(:inc_step_key)
    end

    test "increments multiple times" do
      TestCounterCache.increment(:inc_multi_key)
      TestCounterCache.increment(:inc_multi_key)
      TestCounterCache.increment(:inc_multi_key)
      assert {:ok, 3} === TestCounterCache.get(:inc_multi_key)
    end
  end

  describe "decrement/1,2" do
    test "decrements by 1 by default" do
      TestCounterCache.increment(:dec_key, 3)
      assert :ok === TestCounterCache.decrement(:dec_key)
      assert {:ok, 2} === TestCounterCache.get(:dec_key)
    end

    test "decrements by the given step" do
      TestCounterCache.increment(:dec_step_key, 10)
      assert :ok === TestCounterCache.decrement(:dec_step_key, 4)
      assert {:ok, 6} === TestCounterCache.get(:dec_step_key)
    end

    test "can go negative" do
      assert :ok === TestCounterCache.decrement(:neg_key, 5)
      assert {:ok, -5} === TestCounterCache.get(:neg_key)
    end
  end

  describe "delete/1" do
    test "removes the key so get returns nil" do
      TestCounterCache.increment(:del_key)
      assert :ok === TestCounterCache.delete(:del_key)
      assert {:ok, nil} === TestCounterCache.get(:del_key)
    end

    test "is a no-op for a non-existent key" do
      assert :ok === TestCounterCache.delete(:never_set_del_key)
    end

    test "after delete, incrementing creates a fresh counter" do
      TestCounterCache.increment(:reuse_key, 10)
      TestCounterCache.delete(:reuse_key)
      TestCounterCache.increment(:reuse_key)
      assert {:ok, 1} === TestCounterCache.get(:reuse_key)
    end
  end

  describe "multiple keys are independent" do
    test "counters for different keys do not interfere" do
      TestCounterCache.increment(:key_a, 3)
      TestCounterCache.increment(:key_b, 7)
      assert {:ok, 3} === TestCounterCache.get(:key_a)
      assert {:ok, 7} === TestCounterCache.get(:key_b)
    end
  end
end
