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

    ets_table =
      :ets.new(:"ets_match_spec_#{:erlang.unique_integer([:positive])}", [:set, :public])

    %{ets: ets_table}
  end

  defp load(ets, objects) do
    Enum.each(objects, fn {_k, _v} = obj ->
      TestETSSandboxCache.insert_raw(obj)
      :ets.insert(ets, obj)
    end)
  end

  defp sort_results(list) when is_list(list), do: Enum.sort(list)
  defp sort_results(other), do: other

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

  describe "select/2 match-spec parity with :ets.select/2" do
    test "returns the whole object via $_", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{:"$1", [], [:"$_"]}]

      assert sort_results(TestETSSandboxCache.select(spec)) ===
               sort_results(:ets.select(ets, spec))
    end

    test "returns bindings list via $$", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{{:"$1", :"$2"}, [], [:"$$"]}]

      assert sort_results(TestETSSandboxCache.select(spec)) ===
               sort_results(:ets.select(ets, spec))
    end

    test "double-wrapped body tuple constructs a tuple (idiomatic form)", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}]

      sandbox = TestETSSandboxCache.select(spec)
      ets_result = :ets.select(ets, spec)

      assert sort_results(sandbox) === sort_results(ets_result)

      Enum.each(sandbox, fn result ->
        assert is_tuple(result)
        assert tuple_size(result) === 2
      end)
    end

    test "single-wrapped body tuple raises ArgumentError" do
      spec = [{{:"$1", :"$2"}, [], [{:"$1", :"$2"}]}]

      assert_raise ArgumentError, fn -> TestETSSandboxCache.select(spec) end
    end

    test "invalid match spec raises ArgumentError" do
      assert_raise ArgumentError, fn -> TestETSSandboxCache.select([:not_a_valid_spec]) end
    end

    test "literal term in body is returned as-is", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{{:"$1", :"$2"}, [], [:matched]}]

      assert sort_results(TestETSSandboxCache.select(spec)) ===
               sort_results(:ets.select(ets, spec))
    end

    test "guards filter results", %{ets: ets} do
      load(ets, [{"a", 5}, {"b", 15}, {"c", 25}])

      spec = [{{:"$1", :"$2"}, [{:>, :"$2", 10}], [:"$_"]}]

      assert sort_results(TestETSSandboxCache.select(spec)) ===
               sort_results(:ets.select(ets, spec))
    end

    test "guards with conjunction (:andalso)", %{ets: ets} do
      load(ets, [{"a", 5}, {"b", 15}, {"c", 100}])

      spec = [{{:"$1", :"$2"}, [{:andalso, {:>, :"$2", 10}, {:<, :"$2", 50}}], [:"$2"]}]

      assert sort_results(TestETSSandboxCache.select(spec)) ===
               sort_results(:ets.select(ets, spec))
    end
  end

  describe "select/3 sandbox" do
    test "limit truncates results, returns :end_of_table", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}])

      spec = [{:"$1", [], [:"$_"]}]

      {results, cont} = TestETSSandboxCache.select(spec, 2)

      assert length(results) === 2
      assert cont === :end_of_table
    end
  end

  describe "select_count/2 sandbox" do
    test "counts entries whose body yields true", %{ets: ets} do
      load(ets, [{"a", 5}, {"b", 15}, {"c", 25}])

      spec = [{{:"$1", :"$2"}, [{:>, :"$2", 10}], [true]}]

      assert TestETSSandboxCache.select_count(spec) === :ets.select_count(ets, spec)
    end

    test "ignores non-true body results", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{{:"$1", :"$2"}, [], [:"$2"]}]

      assert TestETSSandboxCache.select_count(spec) === :ets.select_count(ets, spec)
      assert TestETSSandboxCache.select_count(spec) === 0
    end
  end

  describe "select_delete/2 sandbox" do
    test "deletes entries whose body yields true and returns count", %{ets: ets} do
      load(ets, [{"a", 5}, {"b", 15}, {"c", 25}])

      spec = [{{:"$1", :"$2"}, [{:>, :"$2", 10}], [true]}]

      assert TestETSSandboxCache.select_delete(spec) === :ets.select_delete(ets, spec)

      assert {:ok, 5} = TestETSSandboxCache.get("a")
      assert {:ok, nil} = TestETSSandboxCache.get("b")
      assert {:ok, nil} = TestETSSandboxCache.get("c")
    end

    test "leaves entries when body is not true", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{{:"$1", :"$2"}, [], [:"$2"]}]

      assert TestETSSandboxCache.select_delete(spec) === 0
      assert {:ok, 1} = TestETSSandboxCache.get("a")
      assert {:ok, 2} = TestETSSandboxCache.get("b")
    end
  end

  describe "select_replace/2 sandbox" do
    test "replaces matching entries and returns count", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{{:"$1", :"$2"}, [], [{{:"$1", {:+, :"$2", 10}}}]}]

      assert TestETSSandboxCache.select_replace(spec) === :ets.select_replace(ets, spec)

      assert {:ok, 11} = TestETSSandboxCache.get("a")
      assert {:ok, 12} = TestETSSandboxCache.get("b")
    end

    test "raises when body tries to change the key", %{ets: ets} do
      load(ets, [{"a", 1}])

      spec = [{{:"$1", :"$2"}, [], [{{:new_key, :"$2"}}]}]

      assert_raise ArgumentError, fn -> TestETSSandboxCache.select_replace(spec) end
      assert_raise ArgumentError, fn -> :ets.select_replace(ets, spec) end
    end
  end

  describe "select_reverse/2 sandbox" do
    test "returns select results reversed", %{ets: ets} do
      load(ets, [{"a", 1}, {"b", 2}])

      spec = [{:"$1", [], [:"$_"]}]

      forward = TestETSSandboxCache.select(spec)
      reversed = TestETSSandboxCache.select_reverse(spec)

      assert reversed === Enum.reverse(forward)
    end
  end
end
