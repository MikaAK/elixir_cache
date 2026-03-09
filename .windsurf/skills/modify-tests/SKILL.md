---
name: modify-tests
description: "Testing patterns for the elixir_cache project. TRIGGER when: writing or modifying tests, test support modules, test configuration, or test helper functions. Also trigger when working with Cache.Sandbox or Cache.SandboxRegistry test patterns. DO NOT TRIGGER when: writing production code that doesn't involve test infrastructure."
---

# Testing Patterns

## General Rules

- Run tests with `mix test`
- Use `ErrorMessage` structs for error assertions
- Use `refute` instead of `assert !condition`
- Use `is_nil/1` guard instead of `== nil`
- Use `===` and `!==` for strict comparisons
- **Never use `Application.put_env` in tests** — use compile-time config or test-specific function definitions
- When fixing failing tests, first determine whether the code or the test is wrong before choosing what to fix
- Run tests after writing them
- Use `async: true` where possible

## Test Structure

```
test/
├── test_helper.exs           # Starts Cache.SandboxRegistry, then ExUnit
├── cache_test.exs             # Tests for the main Cache module / use Cache macro
├── cache_sandbox_test.exs     # Tests for Cache.Sandbox and SandboxRegistry
├── cache/
│   ├── agent_test.exs         # Cache.Agent adapter tests
│   ├── con_cache_test.exs     # Cache.ConCache adapter tests
│   ├── dets_test.exs          # Cache.DETS adapter tests
│   ├── ets_test.exs           # Cache.ETS adapter tests
│   ├── redis_test.exs         # Cache.Redis adapter tests
│   └── term_encoder_test.exs  # Cache.TermEncoder tests
```

## Cache Sandbox Testing

The project uses `Cache.SandboxRegistry` for per-test cache isolation. Setup in `test/test_helper.exs`:

```elixir
Cache.SandboxRegistry.start_link()
ExUnit.start()
```

In test modules, register caches in `setup`:

```elixir
setup do
  Cache.SandboxRegistry.start([TestCacheModule])
  :ok
end
```

This ensures each test process gets isolated cache keys via sandbox ID prefixing.

## Compile-Time Environment Branching

Use `Mix.env()` at compile time (not available at runtime in releases):

```elixir
if Mix.env() === :test do
  @sandbox true
else
  @sandbox false
end
```

## Test Cache Modules

Tests define inline cache modules with `use Cache` for testing adapters. Example pattern:

```elixir
defmodule TestCache do
  use Cache,
    adapter: Cache.ETS,
    name: :test_cache,
    sandbox?: true,
    opts: [type: :set]
end
```

## Testing GenServers and Supervisors

- Start GenServers with `start_supervised!/1`
- Use `{Cache, [TestCache]}` in supervision tree for integration tests
