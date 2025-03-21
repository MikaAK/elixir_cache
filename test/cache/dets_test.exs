defmodule Cache.DETSTest do
  use ExUnit.Case, async: true

  defmodule TestDETSCache do
    use Cache,
      adapter: Cache.DETS,
      name: :test_dets_cache,
      opts: [file_path: "/tmp/test_dets_cache"]
  end

  setup do
    start_supervised({Cache, [TestDETSCache]})
    Process.sleep(100)

    on_exit(fn ->
      File.rm("/tmp/test_dets_cache.dets")
    end)

    :ok
  end

  describe "match_object/2" do
    test "matches objects in the table" do
      TestDETSCache.insert_raw({:key1, "SomeRandomValue"})
      TestDETSCache.insert_raw({:key2, "SomeRandomValue"})

      result = TestDETSCache.match_object({:_, "SomeRandomValue"})

      assert length(result) === 2
      assert {:key1, "SomeRandomValue"} in result
      assert {:key2, "SomeRandomValue"} in result

      result = TestDETSCache.match_object({:key1, :_})
      assert result === [{:key1, "SomeRandomValue"}]
    end
  end

  describe "member/2" do
    test "checks if a key is in the table" do
      TestDETSCache.insert_raw({:test_key, "test_value"})

      assert TestDETSCache.member(:test_key) === true
      assert TestDETSCache.member(:nonexistent_key) === false
    end
  end

  describe "select/2" do
    test "selects objects using match specification" do
      TestDETSCache.insert_raw({:key1, "value1"})
      TestDETSCache.insert_raw({:key2, "value2"})

      match_spec = [{{:key1, :_}, [], [:'$_']}]
      result = TestDETSCache.select(match_spec)
      assert result === [{:key1, "value1"}]
    end
  end

  describe "info/1" do
    test "returns information about the table" do
      info = TestDETSCache.info()
      assert is_list(info)
      assert Keyword.get(info, :type) === :set
    end
  end

  describe "info/2" do
    test "returns specific information about the table" do
      assert TestDETSCache.info(:type) === :set
    end
  end

  describe "select_delete/2" do
    test "deletes objects using match specification" do
      TestDETSCache.insert_raw({:key1, "value1"})
      TestDETSCache.insert_raw({:key2, "value2"})

      match_spec = [{{:key1, :_}, [], [true]}]
      count = TestDETSCache.select_delete(match_spec)
      assert count === 1

      assert TestDETSCache.member(:key1) === false
      assert TestDETSCache.member(:key2) === true
    end
  end

  describe "match_delete/2" do
    test "deletes objects matching a pattern" do
      TestDETSCache.insert_raw({:key1, "value1"})
      TestDETSCache.insert_raw({:key2, "value2"})

      TestDETSCache.match_delete({:key1, :_})

      assert TestDETSCache.member(:key1) === false
      assert TestDETSCache.member(:key2) === true
    end
  end

  describe "update_counter/3" do
    test "updates a counter in the table" do
      TestDETSCache.insert_raw({:counter, 0})

      result = TestDETSCache.update_counter(:counter, 1)
      assert result === 1

      assert TestDETSCache.match_object({:counter, :_}) === [{:counter, 1}]

      result = TestDETSCache.update_counter(:counter, {2, 5})
      assert result === 6  # 1 + 5
    end
  end

  describe "insert_raw/2" do
    test "inserts raw data into the table" do
      result = TestDETSCache.insert_raw({:raw_key, "raw_value"})
      assert result === :ok

      assert TestDETSCache.member(:raw_key) === true
      assert TestDETSCache.match_object({:raw_key, :_}) === [{:raw_key, "raw_value"}]

      result = TestDETSCache.insert_raw([{:raw_key2, "value2"}, {:raw_key3, "value3"}])
      assert result === :ok

      assert TestDETSCache.member(:raw_key2) === true
      assert TestDETSCache.member(:raw_key3) === true
    end
  end

  if function_exported?(:dets, :to_ets, 1) do
    describe "to_ets/1 and from_ets/2" do
      test "converts between DETS and ETS tables" do
        TestDETSCache.insert_raw({:dets_key, "dets_value"})

        ets_table = TestDETSCache.to_ets()
        assert is_atom(ets_table)

        assert :ets.lookup(ets_table, :dets_key) === [{:dets_key, "dets_value"}]

        :ets.insert(ets_table, {:ets_key, "ets_value"})

        :dets.delete_all_objects(:test_dets_cache)

        result = TestDETSCache.from_ets(ets_table)
        assert result === :ok

        assert TestDETSCache.member(:dets_key) === true
        assert TestDETSCache.member(:ets_key) === true

        :ets.delete(ets_table)
      end
    end
  end
end
