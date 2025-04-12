# How to Test Applications Using ElixirCache

This guide explains how to effectively test applications that use ElixirCache, focusing on the sandbox functionality.

## Using the Sandbox Mode

ElixirCache provides a sandbox mode specifically designed for testing. This ensures that your tests:

1. Are isolated from each other
2. Don't leave lingering cache data between test runs
3. Can run in parallel without conflicts

### Configuring Your Cache for Testing

In your test environment, you can wrap any cache adapter with the sandbox functionality:

```elixir
# In lib/my_app/cache.ex
defmodule MyApp.Cache do
  use Cache,
    adapter: get_cache_adapter(),
    name: :my_app_cache,
    opts: get_cache_opts(),
    # Enable sandbox mode in test environment
    sandbox?: Mix.env() == :test

  defp get_cache_adapter do
    case Mix.env() do
      :test -> Cache.ETS
      :dev -> Cache.ETS
      :prod -> Cache.Redis
    end
  end
  
  defp get_cache_opts do
    case Mix.env() do
      :test -> []
      :dev -> []
      :prod -> [host: "redis.example.com", port: 6379]
    end
  end
end
```

### Setting Up the Sandbox Registry

To use the sandbox functionality in your tests, you need to start the `Cache.SandboxRegistry` in your test setup:

```elixir
# In test/test_helper.exs
ExUnit.start()

# Start the sandbox registry for your tests
{:ok, _pid} = Cache.SandboxRegistry.start_link()

# Start your application's supervision tree
Application.ensure_all_started(:my_app)
```

### Using the Sandbox in Tests

Using the sandbox in your tests is very simple. All you need to do is start the sandbox registry in your setup block:

```elixir
defmodule MyApp.CacheTest do
  use ExUnit.Case, async: true

  defmodule TestCache do
    use Cache,
      adapter: Cache.Redis,  # The actual adapter doesn't matter in sandbox mode
      name: :test_cache,
      opts: [],
      sandbox?: Mix.env() === :test
  end

  setup do
    # This single line is all you need to set up sandbox isolation
    Cache.SandboxRegistry.start(TestCache)
    :ok
  end
  
  test "can store and retrieve values" do
    assert :ok = TestCache.put("test-key", "test-value")
    assert {:ok, "test-value"} = TestCache.get("test-key")
  end
  
  test "can handle complex data structures" do
    data = %{users: [%{name: "Alice"}, %{name: "Bob"}]}
    assert :ok = TestCache.put("complex-key", data)
    assert {:ok, ^data} = TestCache.get("complex-key")
  end

  test "provides isolation between tests" do
    # This will return nil because each test has an isolated cache
    assert {:ok, nil} = TestCache.get("test-key")
  end
end
```


## Tips for Testing with ElixirCache

1. **Always use the sandbox in tests**: This prevents interference between tests.
2. **Clean up after each test**: Use `on_exit` to unregister from the sandbox.
3. **Use unique keys**: Even with sandboxing, using descriptive, unique keys makes debugging easier.
4. **Test edge cases**: Including cache misses, errors, and TTL expiration.
5. **Consider using fixtures**: For commonly cached data structures.
6. **Verify telemetry events**: If your application relies on cache metrics.
