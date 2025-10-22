defmodule Cache.ETSTest do
  use ExUnit.Case, async: true

  # Create a separate module for the Cache adapter functionality
  defmodule TestETSCache do
    use Cache,
      adapter: Cache.ETS,
      name: :test_ets_cache,
      opts: []
  end

  setup do
    start_supervised({Cache, [TestETSCache]})

    Process.sleep(100)

    :ok
  end

  describe "match_object/2" do
    test "matches objects in the table" do
      TestETSCache.insert_raw({:key1, "SomeValue"})
      TestETSCache.insert_raw({:key2, "SomeValue"})

      result = TestETSCache.match_object({:_, "SomeValue"})

      assert length(result) === 2

      assert {:key1, "SomeValue"} in result
      assert {:key2, "SomeValue"} in result

      result = TestETSCache.match_object({:key1, :_})
      assert result === [{:key1, "SomeValue"}]
    end
  end

  describe "member/2" do
    test "checks if a key is in the table" do
      TestETSCache.insert_raw({:test_key, "test_value"})

      assert TestETSCache.member(:test_key) === true
      assert TestETSCache.member(:nonexistent_key) === false
    end
  end

  describe "select/2" do
    test "selects objects using match specification" do
      TestETSCache.insert_raw({:key1, "value1"})
      TestETSCache.insert_raw({:key2, "value2"})

      match_spec = [{{:key1, :_}, [], [:"$_"]}]
      result = TestETSCache.select(match_spec)
      assert result === [{:key1, "value1"}]
    end
  end

  describe "info/1" do
    test "returns information about the table" do
      info = TestETSCache.info()
      assert is_list(info)
      assert Keyword.get(info, :name) === :test_ets_cache
      assert Keyword.get(info, :type) === :set
    end
  end

  describe "info/2" do
    test "returns specific information about the table" do
      assert TestETSCache.info(:name) === :test_ets_cache
      assert TestETSCache.info(:type) === :set
    end
  end

  describe "select_delete/2" do
    test "deletes objects using match specification" do
      # Insert test data directly using ETS
      :ets.insert(:test_ets_cache, {:key1, "value1"})
      :ets.insert(:test_ets_cache, {:key2, "value2"})

      match_spec = [{{:key1, :_}, [], [true]}]
      count = TestETSCache.select_delete(match_spec)
      assert count === 1

      assert TestETSCache.member(:key1) === false
      assert TestETSCache.member(:key2) === true
    end
  end

  describe "match_delete/2" do
    test "deletes objects matching a pattern" do
      # Insert test data directly using ETS
      :ets.insert(:test_ets_cache, {:key1, "value1"})
      :ets.insert(:test_ets_cache, {:key2, "value2"})

      TestETSCache.match_delete({:key1, :_})

      assert TestETSCache.member(:key1) === false
      assert TestETSCache.member(:key2) === true
    end
  end

  describe "update_counter/3" do
    test "updates a counter in the table" do
      :ets.insert(:test_ets_cache, {:counter, 0})

      result = TestETSCache.update_counter(:counter, 1)
      assert result === 1

      assert TestETSCache.match_object({:counter, :_}) === [{:counter, 1}]

      result = TestETSCache.update_counter(:counter, {2, 5})
      # 1 + 5
      assert result === 6
    end
  end

  describe "insert_raw/2" do
    test "inserts raw data into the table" do
      result = TestETSCache.insert_raw({:raw_key, "raw_value"})
      assert result === true

      assert TestETSCache.member(:raw_key) === true
      assert TestETSCache.match_object({:raw_key, :_}) === [{:raw_key, "raw_value"}]

      result = TestETSCache.insert_raw([{:raw_key2, "value2"}, {:raw_key3, "value3"}])
      assert result === true

      assert TestETSCache.member(:raw_key2) === true
      assert TestETSCache.member(:raw_key3) === true
    end
  end

  if function_exported?(:dets, :to_ets, 1) do
    describe "to_dets/2 and from_dets/2" do
      test "converts between ETS and DETS tables" do
        dets_file = "/tmp/test_dets_#{:rand.uniform(1000)}"
        {:ok, dets_table} = :dets.open_file(:test_dets_table, file: String.to_charlist(dets_file))

        # Insert test data directly using ETS
        :ets.insert(:test_ets_cache, {:ets_key, "ets_value"})

        result = TestETSCache.to_dets(:test_dets_table)
        assert result === :ok

        assert :dets.lookup(:test_dets_table, :ets_key) === [{:ets_key, "ets_value"}]

        :dets.insert(:test_dets_table, {:dets_key, "dets_value"})

        :ets.delete_all_objects(:test_ets_cache)

        result = TestETSCache.from_dets(:test_dets_table)
        assert result === :ok

        assert TestETSCache.member(:ets_key) === true
        assert TestETSCache.member(:dets_key) === true

        :dets.close(:test_dets_table)
        File.rm(dets_file)
      end
    end
  end
end
