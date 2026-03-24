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

  describe "rehydration_path" do
    defmodule RehydrateTestCache do
      use Cache,
        adapter: Cache.ETS,
        name: :rehydrate_test_cache,
        opts: [rehydration_path: "/tmp/ets_test"]
    end

    defmodule NewTableTestCache do
      use Cache,
        adapter: Cache.ETS,
        name: :new_table_test_cache,
        opts: [rehydration_path: "/tmp/ets_test"]
    end

    test "rehydrates from file on startup" do
      File.mkdir_p!("/tmp/ets_test")
      on_exit(fn -> File.rm_rf("/tmp/ets_test") end)

      encoded_value = Cache.TermEncoder.encode("persisted_value", nil)

      :ets.new(:rehydrate_test_cache, [:set, :public, :named_table])
      :ets.insert(:rehydrate_test_cache, {:persisted_key, encoded_value})
      :ets.tab2file(:rehydrate_test_cache, ~c"/tmp/ets_test/rehydrate_test_cache.ets")
      :ets.delete(:rehydrate_test_cache)

      start_supervised!(
        %{
          id: :rehydrate_cache_sup,
          type: :supervisor,
          start: {Cache, :start_link, [[RehydrateTestCache], [name: :rehydrate_cache_sup]]}
        }
      )

      Process.sleep(100)

      assert {:ok, "persisted_value"} === RehydrateTestCache.get(:persisted_key)
    end

    test "creates new table when no file exists" do
      File.mkdir_p!("/tmp/ets_test")
      on_exit(fn -> File.rm_rf("/tmp/ets_test") end)

      start_supervised!(
        %{
          id: :new_table_cache_sup,
          type: :supervisor,
          start: {Cache, :start_link, [[NewTableTestCache], [name: :new_table_cache_sup]]}
        }
      )

      Process.sleep(100)

      assert {:ok, nil} === NewTableTestCache.get(:nonexistent_key)
      assert :ok === NewTableTestCache.put(:new_key, "new_value")
      assert {:ok, "new_value"} === NewTableTestCache.get(:new_key)
    end
  end

  describe "all/0" do
    test "returns a list of ETS tables including the test table" do
      tables = TestETSCache.all()
      assert is_list(tables)
      assert :test_ets_cache in tables
    end
  end

  describe "delete_all_objects/0" do
    test "removes all objects from the table" do
      TestETSCache.insert_raw({:a, 1})
      TestETSCache.insert_raw({:b, 2})
      TestETSCache.delete_all_objects()
      assert TestETSCache.tab2list() === []
    end
  end

  describe "delete_object/1" do
    test "deletes exact object from the table" do
      TestETSCache.insert_raw({:obj_key, "obj_val"})
      TestETSCache.delete_object({:obj_key, "obj_val"})
      refute TestETSCache.member(:obj_key)
    end
  end

  describe "delete_table/0 and recreation" do
    defmodule DeleteTableCache do
      use Cache,
        adapter: Cache.ETS,
        name: :delete_table_test_cache,
        opts: []
    end

    test "deletes the entire table" do
      start_supervised!(%{
        id: :delete_table_sup,
        type: :supervisor,
        start: {Cache, :start_link, [[DeleteTableCache], [name: :delete_table_sup]]}
      })

      Process.sleep(100)
      DeleteTableCache.insert_raw({:key, "val"})
      assert DeleteTableCache.delete_table() === true
    end
  end

  describe "first/0 and last/0" do
    test "returns first and last keys" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:alpha, 1})
      TestETSCache.insert_raw({:beta, 2})

      first = TestETSCache.first()
      last = TestETSCache.last()
      refute first === :"$end_of_table"
      refute last === :"$end_of_table"
    end

    test "returns $end_of_table for empty table" do
      TestETSCache.delete_all_objects()
      assert TestETSCache.first() === :"$end_of_table"
      assert TestETSCache.last() === :"$end_of_table"
    end
  end

  describe "next/1 and prev/1" do
    test "navigates between keys" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:k1, 1})
      TestETSCache.insert_raw({:k2, 2})

      first_key = TestETSCache.first()
      next_key = TestETSCache.next(first_key)
      refute next_key === :"$end_of_table"
    end
  end

  describe "foldl/2 and foldr/2" do
    test "folds over all objects" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:x, 1})
      TestETSCache.insert_raw({:y, 2})

      sum = TestETSCache.foldl(fn {_key, val}, acc -> acc + val end, 0)
      assert sum === 3

      sum_r = TestETSCache.foldr(fn {_key, val}, acc -> acc + val end, 0)
      assert sum_r === 3
    end
  end

  describe "info/0 and info/1" do
    test "returns full and specific info" do
      info = TestETSCache.info()
      assert Keyword.get(info, :name) === :test_ets_cache
      assert TestETSCache.info(:size) >= 0
    end
  end

  describe "insert_new/1" do
    test "inserts only when key does not exist" do
      TestETSCache.delete_all_objects()
      assert TestETSCache.insert_new({:unique, "first"}) === true
      assert TestETSCache.insert_new({:unique, "second"}) === false
      assert TestETSCache.lookup(:unique) === [{:unique, "first"}]
    end
  end

  describe "lookup/1 and lookup_element/2" do
    test "looks up objects and elements" do
      TestETSCache.insert_raw({:lk_key, "lk_val"})
      assert TestETSCache.lookup(:lk_key) === [{:lk_key, "lk_val"}]
      assert TestETSCache.lookup_element(:lk_key, 2) === "lk_val"
    end
  end

  describe "match_pattern/1 and match_pattern/2" do
    test "matches with pattern" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:mp1, "a"})
      TestETSCache.insert_raw({:mp2, "b"})

      result = TestETSCache.match_pattern({:"$1", :_})
      assert length(result) === 2

      {matches, _cont} = TestETSCache.match_pattern({:"$1", :_}, 1)
      assert length(matches) === 1
    end
  end

  describe "match_object/1 with continuation" do
    test "continues match_object with limit" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:mo1, "a"})
      TestETSCache.insert_raw({:mo2, "b"})
      TestETSCache.insert_raw({:mo3, "c"})

      {first_batch, continuation} = TestETSCache.match_object({:_, :_}, 2)
      assert length(first_batch) === 2
      refute continuation === :"$end_of_table"
    end
  end

  describe "match_spec_compile/1 and match_spec_run/2" do
    test "compiles and runs match spec" do
      spec = [{{:_, :"$1"}, [], [:"$1"]}]
      compiled = TestETSCache.match_spec_compile(spec)
      assert TestETSCache.is_compiled_ms(compiled) === true

      result = TestETSCache.match_spec_run([{:k, "v"}], compiled)
      assert result === ["v"]
    end
  end

  describe "rename/1" do
    defmodule RenameTestCache do
      use Cache,
        adapter: Cache.ETS,
        name: :rename_test_cache,
        opts: []
    end

    test "renames the table" do
      start_supervised!(%{
        id: :rename_test_sup,
        type: :supervisor,
        start: {Cache, :start_link, [[RenameTestCache], [name: :rename_test_sup]]}
      })

      Process.sleep(100)
      RenameTestCache.insert_raw({:rkey, "rval"})
      RenameTestCache.rename(:renamed_cache)
      assert :ets.lookup(:renamed_cache, :rkey) === [{:rkey, "rval"}]
      :ets.rename(:renamed_cache, :rename_test_cache)
    end
  end

  describe "safe_fixtable/1" do
    test "fixes and unfixes the table" do
      assert TestETSCache.safe_fixtable(true) === true
      assert TestETSCache.safe_fixtable(false) === true
    end
  end

  describe "select_count/1" do
    test "counts matching objects" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:sc1, "a"})
      TestETSCache.insert_raw({:sc2, "b"})

      count = TestETSCache.select_count([{:_, [], [true]}])
      assert count === 2
    end
  end

  describe "select/2 with limit" do
    test "selects with limit and continuation" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:sl1, "a"})
      TestETSCache.insert_raw({:sl2, "b"})

      {results, _cont} = TestETSCache.select([{:_, [], [:"$_"]}], 1)
      assert length(results) === 1
    end
  end

  describe "select_replace/1" do
    test "replaces matching objects" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:sr1, "old"})

      match_spec = [{{:sr1, :_}, [], [{{:sr1, "new"}}]}]
      count = TestETSCache.select_replace(match_spec)
      assert count === 1
      assert TestETSCache.lookup(:sr1) === [{:sr1, "new"}]
    end
  end

  describe "select_reverse/1" do
    test "returns results in reverse" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:rv1, "a"})
      TestETSCache.insert_raw({:rv2, "b"})

      result = TestETSCache.select_reverse([{:_, [], [:"$_"]}])
      assert length(result) === 2
    end
  end

  describe "select_reverse/2 with limit" do
    test "returns results in reverse with limit" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:rvl1, "a"})
      TestETSCache.insert_raw({:rvl2, "b"})

      {results, _cont} = TestETSCache.select_reverse([{:_, [], [:"$_"]}], 1)
      assert length(results) === 1
    end
  end

  describe "repair_continuation/2" do
    test "repairs a continuation" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:rc1, "a"})
      TestETSCache.insert_raw({:rc2, "b"})

      match_spec = [{{:_, :_}, [], [:"$_"]}]
      {_results, continuation} = TestETSCache.select(match_spec, 1)
      repaired = TestETSCache.repair_continuation(continuation, match_spec)
      assert is_tuple(repaired)
    end
  end

  describe "slot/1" do
    test "returns objects at slot" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:slot_key, "slot_val"})
      result = TestETSCache.slot(0)
      assert is_list(result)
    end
  end

  describe "tab2file/1 and file2tab/1 and tabfile_info/1" do
    test "dumps and reads table from file" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:tf_key, "tf_val"})
      file = ~c"/tmp/test_ets_tab2file_#{:rand.uniform(100_000)}"

      assert :ok = TestETSCache.tab2file(file)
      assert {:ok, info} = TestETSCache.tabfile_info(file)
      assert is_list(info)

      File.rm(to_string(file))
    end
  end

  describe "tab2file/2 with options" do
    test "dumps table with extended_info" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:tf2_key, "val"})
      file = ~c"/tmp/test_ets_tab2file2_#{:rand.uniform(100_000)}"

      assert :ok = TestETSCache.tab2file(file, extended_info: [:md5sum])
      assert {:ok, info} = TestETSCache.tabfile_info(file)
      assert is_list(info)

      File.rm(to_string(file))
    end
  end

  describe "file2tab/2 with options" do
    defmodule File2TabTestCache do
      use Cache,
        adapter: Cache.ETS,
        name: :file2tab_test_cache,
        opts: []
    end

    test "reads table with verify option" do
      start_supervised!(%{
        id: :file2tab_sup,
        type: :supervisor,
        start: {Cache, :start_link, [[File2TabTestCache], [name: :file2tab_sup]]}
      })

      Process.sleep(100)
      File2TabTestCache.insert_raw({:fb_key, "val"})
      file = ~c"/tmp/test_ets_file2tab_#{:rand.uniform(100_000)}"

      File2TabTestCache.tab2file(file, extended_info: [:md5sum])
      :ets.delete(:file2tab_test_cache)

      assert {:ok, _} = File2TabTestCache.file2tab(file, [verify: true])

      File.rm(to_string(file))
    end
  end

  describe "tab2list/0" do
    test "returns all objects as a list" do
      TestETSCache.delete_all_objects()
      TestETSCache.insert_raw({:tl1, "a"})
      TestETSCache.insert_raw({:tl2, "b"})

      list = TestETSCache.tab2list()
      assert length(list) === 2
    end
  end

  describe "table/0" do
    test "returns a QLC query handle" do
      handle = TestETSCache.table()
      assert is_reference(handle) or is_tuple(handle)
    end
  end

  describe "table/1 with options" do
    test "returns a QLC query handle with traverse option" do
      handle = TestETSCache.table(traverse: :first_next)
      assert is_reference(handle) or is_tuple(handle)
    end
  end

  describe "take/1" do
    test "returns and removes object" do
      TestETSCache.insert_raw({:take_key, "take_val"})
      result = TestETSCache.take(:take_key)
      assert result === [{:take_key, "take_val"}]
      refute TestETSCache.member(:take_key)
    end
  end

  describe "test_ms/2" do
    test "tests match spec against a tuple" do
      spec = [{{:"$1", :"$2"}, [], [:"$2"]}]
      result = TestETSCache.test_ms({:key, "value"}, spec)
      assert result === {:ok, "value"}
    end
  end

  describe "update_counter/3 with default" do
    test "creates counter with default if key doesn't exist" do
      result = TestETSCache.update_counter(:new_counter, 1, {:new_counter, 0})
      assert result === 1
    end
  end

  describe "update_element/2" do
    test "updates specific element of an object" do
      TestETSCache.insert_raw({:ue_key, "old_val"})
      assert TestETSCache.update_element(:ue_key, {2, "new_val"}) === true
      assert TestETSCache.lookup(:ue_key) === [{:ue_key, "new_val"}]
    end
  end

  describe "whereis/0" do
    test "returns the tid of the named table" do
      tid = TestETSCache.whereis()
      assert is_reference(tid)
    end
  end



  describe "opts_definition/1" do
    test "validates valid opts" do
      assert {:ok, _} = Cache.ETS.opts_definition(type: :set)
    end

    test "rejects invalid opts" do
      assert {:error, _} = Cache.ETS.opts_definition(type: :invalid)
    end

    test "rejects non-keyword list" do
      assert {:error, "expected a keyword list"} = Cache.ETS.opts_definition([1, 2, 3])
    end

    test "rejects non-list" do
      assert {:error, "expected a keyword list"} = Cache.ETS.opts_definition("not a list")
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
