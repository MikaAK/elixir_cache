# How to Test Applications Using ElixirCache

This guide explains how to effectively test applications that use ElixirCache, focusing on the sandbox functionality.

## Using the Sandbox Mode

ElixirCache provides a sandbox mode that gives each test its own isolated cache
namespace. This ensures your tests:

1. Are isolated from each other
2. Don't leave lingering cache data between test runs
3. Can run in parallel without conflicts

### Configuring Your Cache

Use `sandbox?: Mix.env() === :test` on your cache module. The adapter stays the
same in every environment — the sandbox wraps whatever adapter you choose:

```elixir
defmodule MyApp.Cache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_cache,
    opts: [uri: "redis://localhost:6379"],
    sandbox?: Mix.env() === :test
end
```

When `sandbox?` is `true`, `Cache.Sandbox` is used as the adapter automatically.
You do not need to switch adapters between environments.

### Setting Up the Sandbox Registry

Add `Cache.SandboxRegistry.start_link()` to your `test/test_helper.exs`:

```elixir
# In test/test_helper.exs
Cache.SandboxRegistry.start_link()
ExUnit.start()
```

### Using the Sandbox in Tests

Register your cache in each test's `setup` block with
`Cache.SandboxRegistry.start/1`. This starts the cache supervisor and
registers the current test process for isolation:

```elixir
defmodule MyApp.CacheTest do
  use ExUnit.Case, async: true

  setup do
    Cache.SandboxRegistry.start(MyApp.Cache)
    :ok
  end

  test "stores and retrieves values" do
    assert :ok === MyApp.Cache.put("key", "value")
    assert {:ok, "value"} === MyApp.Cache.get("key")
  end

  test "each test is isolated" do
    assert {:ok, nil} === MyApp.Cache.get("key")
  end
end
```

## Tips for Testing with ElixirCache

1. **Always use `sandbox?: Mix.env() === :test`**: Keep the same adapter everywhere — the sandbox handles isolation.
2. **Use `Cache.SandboxRegistry.start/1` in setup**: This is the only line needed per test.
3. **Tests can be `async: true`**: Each test gets its own sandbox namespace.
4. **Test edge cases**: Cache misses, errors, and TTL expiration.
5. **Verify telemetry events**: If your application relies on cache metrics.
