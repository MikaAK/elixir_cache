defmodule Cache.ConCacheTest do
  @moduledoc """
  ConCache-adapter-specific tests.

  """
  use ExUnit.Case, async: true

  defmodule ConCacheAdapter do
    use Cache,
      adapter: Cache.ConCache,
      name: :test_con_cache_real_adapter,
      opts: []
  end

  @ttl :timer.seconds(5)

  setup do
    key = Faker.UUID.v4()

    start_supervised!({Cache, [ConCacheAdapter]})

    %{key: key}
  end

  describe "&get_or_store/3" do
    test "get/set", %{key: key} do
      assert "test_value" === ConCacheAdapter.get_or_store(key, @ttl, fn -> "test_value" end)
      assert "test_value" === ConCacheAdapter.get_or_store(key, @ttl, fn -> raise "not used" end)
    end

    test "uses fetch function exactly once", %{key: key} do
      assert "VALUE" ===
               ConCacheAdapter.get_or_store(key, @ttl, fn ->
                 Process.sleep(1_000)
                 "VALUE"
               end)

      Process.sleep(200)

      assert "VALUE" === ConCacheAdapter.get_or_store(key, @ttl, fn -> raise "not used" end)
    end
  end

  describe "&dirty_get_or_store/3" do
    test "get/set", %{key: key} do
      assert "test_value" === ConCacheAdapter.dirty_get_or_store(key, fn -> "test_value" end)
      assert "test_value" === ConCacheAdapter.dirty_get_or_store(key, fn -> raise "not used" end)
    end
  end
end
