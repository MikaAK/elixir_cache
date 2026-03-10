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

## Using Cache.CaseTemplate

For applications with many test files, repeating `Cache.SandboxRegistry.start/1` in every
`setup` block quickly becomes tedious. `Cache.CaseTemplate` lets you define a single
`CacheCase` module that automatically starts the right caches for every test that uses it.

### Create a CacheCase module

Define a `CacheCase` module in your application's test support directory:

```elixir
# test/support/cache_case.ex
defmodule MyApp.CacheCase do
  use Cache.CaseTemplate, default_caches: [MyApp.UserCache, MyApp.SessionCache]
end
```

Or let `Cache.CaseTemplate` discover caches at runtime by inspecting a running supervisor:

```elixir
defmodule MyApp.CacheCase do
  use Cache.CaseTemplate, supervisors: [MyApp.Supervisor]
end
```

When `:supervisors` is used, `Cache.CaseTemplate` finds the `Cache` supervisor child at
test setup time and returns all cache modules started under it. This keeps your test setup
in sync with production automatically.

### Use the CacheCase in test files

```elixir
defmodule MyApp.UserTest do
  use ExUnit.Case, async: true
  use MyApp.CacheCase

  test "caches are isolated per test" do
    assert {:ok, nil} = MyApp.UserCache.get("key")
    assert :ok = MyApp.UserCache.put("key", "value")
    assert {:ok, "value"} = MyApp.UserCache.get("key")
  end
end
```

To start additional caches only for a specific test file, pass them via `:caches`:

```elixir
defmodule MyApp.AdminTest do
  use ExUnit.Case, async: true
  use MyApp.CacheCase, caches: [MyApp.AdminCache]

  test "admin cache is also started" do
    assert {:ok, nil} = MyApp.AdminCache.get("key")
  end
end
```

### Available options

**For `use Cache.CaseTemplate`** (when defining a `CacheCase` module):

- `:default_caches` — list of cache modules to start for every test
- `:supervisors` — list of supervisor atoms; their `Cache` children are discovered at runtime

**For `use MyApp.CacheCase`** (in a test file):

- `:caches` — additional cache modules for this test file only
- `:sleep` — milliseconds to sleep after starting caches (default: `10`)

### Duplicate detection

If the same cache module appears in both `:default_caches` and `:caches`, `Cache.CaseTemplate`
raises at setup time with a clear error listing the duplicates, so collisions are caught early.

## Tips for Testing with ElixirCache

1. **Always use `sandbox?: Mix.env() === :test`**: Keep the same adapter everywhere — the sandbox handles isolation.
2. **Use `Cache.CaseTemplate`** for apps with many test files to avoid repeating setup boilerplate.
3. **Use `Cache.SandboxRegistry.start/1` in setup** for individual test files that don't share a `CacheCase`.
4. **Tests can be `async: true`**: Each test gets its own sandbox namespace.
5. **Test edge cases**: Cache misses, errors, and TTL expiration.
6. **Verify telemetry events**: If your application relies on cache metrics.
