defmodule Cache.CounterTest do
  use ExUnit.Case, async: true

  defmodule TestCounterCache do
    use Cache,
      adapter: Cache.Counter,
      name: :test_counter_cache,
      opts: [initial_size: 64]
  end

  setup do
    start_supervised({Cache, [TestCounterCache]})
    Process.sleep(50)
    :ok
  end

  describe "get/1" do
    test "returns 0 for a slot that has never been incremented" do
      assert {:ok, 0} === TestCounterCache.get(0)
    end

    test "returns integer value after increment" do
      TestCounterCache.increment(0)
      assert {:ok, 1} === TestCounterCache.get(0)
    end

    test "returns error for out-of-bounds index" do
      assert {:error, %ErrorMessage{code: :bad_request}} = TestCounterCache.get(64)
    end
  end

  describe "put/2 as increment/decrement" do
    test "put with 1 increments the counter" do
      assert :ok === TestCounterCache.put(0, 1)
      assert {:ok, 1} === TestCounterCache.get(0)
      assert :ok === TestCounterCache.put(0, 1)
      assert {:ok, 2} === TestCounterCache.get(0)
    end

    test "put with -1 decrements the counter" do
      TestCounterCache.put(1, 1)
      TestCounterCache.put(1, 1)
      assert :ok === TestCounterCache.put(1, -1)
      assert {:ok, 1} === TestCounterCache.get(1)
    end

    test "put with 0 returns an error" do
      assert {:error, _} = TestCounterCache.put(0, 0)
    end

    test "put with 2 returns an error" do
      assert {:error, _} = TestCounterCache.put(0, 2)
    end

    test "put with a string returns an error" do
      assert {:error, _} = TestCounterCache.put(0, "up")
    end
  end

  describe "increment/1,2" do
    test "increments by 1 by default" do
      assert :ok === TestCounterCache.increment(2)
      assert {:ok, 1} === TestCounterCache.get(2)
    end

    test "increments by the given step" do
      assert :ok === TestCounterCache.increment(3, 5)
      assert {:ok, 5} === TestCounterCache.get(3)
    end

    test "increments multiple times" do
      TestCounterCache.increment(4)
      TestCounterCache.increment(4)
      TestCounterCache.increment(4)
      assert {:ok, 3} === TestCounterCache.get(4)
    end
  end

  describe "decrement/1,2" do
    test "decrements by 1 by default" do
      TestCounterCache.increment(5, 3)
      assert :ok === TestCounterCache.decrement(5)
      assert {:ok, 2} === TestCounterCache.get(5)
    end

    test "decrements by the given step" do
      TestCounterCache.increment(6, 10)
      assert :ok === TestCounterCache.decrement(6, 4)
      assert {:ok, 6} === TestCounterCache.get(6)
    end

    test "can go negative" do
      assert :ok === TestCounterCache.decrement(7, 5)
      assert {:ok, -5} === TestCounterCache.get(7)
    end
  end

  describe "delete/1" do
    test "zeroes the slot" do
      TestCounterCache.increment(8)
      assert :ok === TestCounterCache.delete(8)
      assert {:ok, 0} === TestCounterCache.get(8)
    end

    test "is a no-op for a slot that has never been incremented" do
      assert :ok === TestCounterCache.delete(9)
    end

    test "after delete, incrementing starts fresh from 0" do
      TestCounterCache.increment(10, 10)
      TestCounterCache.delete(10)
      TestCounterCache.increment(10)
      assert {:ok, 1} === TestCounterCache.get(10)
    end
  end

  describe "multiple keys are independent" do
    test "counters for different keys do not interfere" do
      TestCounterCache.increment(11, 3)
      TestCounterCache.increment(12, 7)
      assert {:ok, 3} === TestCounterCache.get(11)
      assert {:ok, 7} === TestCounterCache.get(12)
    end
  end

  describe "concurrency" do
    test "concurrent increments on the same slot are all counted" do
      tasks = for _ <- 1..100, do: Task.async(fn -> TestCounterCache.increment(13) end)
      Enum.each(tasks, &Task.await/1)
      assert {:ok, 100} === TestCounterCache.get(13)
    end
  end
end
