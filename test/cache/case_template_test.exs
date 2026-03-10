defmodule Cache.CaseTemplateTest do
  use ExUnit.Case, async: true

  defmodule TestCache do
    use Cache,
      adapter: Cache.Agent,
      name: :case_template_test_cache,
      sandbox?: true,
      opts: []
  end

  defmodule TestCache2 do
    use Cache,
      adapter: Cache.Agent,
      name: :case_template_test_cache_2,
      sandbox?: true,
      opts: []
  end

  defmodule TestCacheCase do
    use Cache.CaseTemplate, default_caches: [TestCache]
  end

  defmodule TestCaseCaseWithExtra do
    use Cache.CaseTemplate, default_caches: [TestCache]
  end

  describe "validate_uniq!/1" do
    test "returns the list when all caches are unique" do
      assert [TestCache, TestCache2] === Cache.CaseTemplate.validate_uniq!([TestCache, TestCache2])
    end

    test "raises when duplicates are present" do
      assert_raise RuntimeError, ~r/specified more than once/, fn ->
        Cache.CaseTemplate.validate_uniq!([TestCache, TestCache, TestCache2])
      end
    end

    test "includes the duplicate module names in the error message" do
      assert_raise RuntimeError, ~r/#{inspect(TestCache)}/, fn ->
        Cache.CaseTemplate.validate_uniq!([TestCache, TestCache])
      end
    end
  end

  describe "inferred_caches/1" do
    test "returns empty list for empty supervisors list" do
      assert [] === Cache.CaseTemplate.inferred_caches([])
    end

    test "raises when supervisor is not started" do
      assert_raise RuntimeError, ~r/is not started/, fn ->
        Cache.CaseTemplate.inferred_caches(NonExistentSupervisor)
      end
    end

    test "raises when supervisor has no Cache child" do
      {:ok, sup_pid} = Supervisor.start_link([], strategy: :one_for_one)

      sup_name = :"test_sup_#{System.unique_integer([:positive])}"
      Process.register(sup_pid, sup_name)

      assert_raise RuntimeError, ~r/no Cache child supervisor/, fn ->
        Cache.CaseTemplate.inferred_caches(sup_name)
      end
    after
      :ok
    end
  end

  describe "use Cache.CaseTemplate" do
    test "raises when :caches key is used instead of :default_caches" do
      assert_raise RuntimeError, ~r/:caches is not valid here/, fn ->
        Code.eval_string("""
        defmodule BadCacheCase do
          use Cache.CaseTemplate, caches: [Cache.CaseTemplateTest.TestCache]
        end
        """)
      end
    end
  end

end

defmodule Cache.CaseTemplateTest.IsolationTest do
  use ExUnit.Case
  use Cache.CaseTemplateTest.TestCacheCase

  alias Cache.CaseTemplateTest.TestCache

  test "cache is started and isolated per test" do
    assert {:ok, nil} = TestCache.get("some_key")
    assert :ok = TestCache.put("some_key", "value")
    assert {:ok, "value"} = TestCache.get("some_key")
  end

  test "state does not leak between tests" do
    assert {:ok, nil} = TestCache.get("some_key")
  end
end

defmodule Cache.CaseTemplateTest.ExtraCachesTest do
  use ExUnit.Case
  use Cache.CaseTemplateTest.TestCaseCaseWithExtra, caches: [Cache.CaseTemplateTest.TestCache2]

  alias Cache.CaseTemplateTest.TestCache
  alias Cache.CaseTemplateTest.TestCache2

  test "both default and extra caches are started and isolated" do
    assert {:ok, nil} = TestCache.get("key")
    assert {:ok, nil} = TestCache2.get("key")
    assert :ok = TestCache.put("key", "a")
    assert :ok = TestCache2.put("key", "b")
    assert {:ok, "a"} = TestCache.get("key")
    assert {:ok, "b"} = TestCache2.get("key")
  end
end
