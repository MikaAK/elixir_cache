---
name: modify-caching
description: "Caching patterns for the elixir_cache project. TRIGGER when: writing or modifying caching code involving Redis, ETS, elixir_cache, Cachex, or any of the _cache apps. Also trigger when working with RedisLock, Cache.Redis, Cache.ETS, or cache sandbox testing. DO NOT TRIGGER when: working with code that doesn't involve caching layers."
supporting_files:
  - "references/elixir-cache-reference.md"
---

# Caching Patterns

For the full library API reference, read `references/elixir-cache-reference.md`.

## Architecture

`elixir_cache` provides a unified caching API via the `use Cache` macro with pluggable adapters:

```
lib/
├── cache.ex              # Main module: behaviour, `use` macro, delegation
├── cache/
│   ├── agent.ex          # Cache.Agent adapter (simple Agent-based)
│   ├── con_cache.ex      # Cache.ConCache adapter (wraps con_cache library)
│   ├── dets.ex           # Cache.DETS adapter (disk-persisted via Erlang DETS)
│   ├── ets.ex            # Cache.ETS adapter (high-performance in-memory)
│   ├── redis.ex          # Cache.Redis adapter (Redix + Poolboy)
│   ├── sandbox.ex        # Cache.Sandbox adapter (test isolation)
│   ├── sandbox_registry.ex  # Process registry for sandbox isolation
│   ├── term_encoder.ex   # Binary term encoding/decoding
│   └── metrics.ex        # Telemetry event definitions
```

## Cache Behaviour

All adapters implement `@behaviour Cache`:

```elixir
@callback child_spec({cache_name :: atom, cache_opts :: Keyword.t()}) :: Supervisor.child_spec()
@callback opts_definition() :: Keyword.t()
@callback start_link(cache_opts :: Keyword.t()) :: {:ok, pid()} | {:error, term()} | :ignore
@callback put(cache_name, key, ttl, value) :: :ok | ErrorMessage.t()
@callback put(cache_name, key, ttl, value, opts) :: :ok | ErrorMessage.t()
@callback get(cache_name, key) :: ErrorMessage.t_res(any)
@callback get(cache_name, key, opts) :: ErrorMessage.t_res(any)
@callback delete(cache_name, key) :: :ok | ErrorMessage.t()
@callback delete(cache_name, key, opts) :: :ok | ErrorMessage.t()
```

## `use Cache` Macro

The macro generates public API functions (`get/1`, `put/2`, `put/3`, `delete/1`, `get_or_create/2`, etc.) plus adapter-specific functions if the adapter exports `__using__/1`.

**Required options:** `adapter`, `name`
**Optional:** `sandbox?`, `opts`

## Adapters

| Adapter | Description |
|---------|-------------|
| `Cache.Agent` | Simple agent-based caching |
| `Cache.DETS` | Disk-persisted caching with Erlang DETS |
| `Cache.ETS` | High-performance in-memory cache with ETS |
| `Cache.Redis` | Redis adapter using Redix & Poolboy, supports JSON and Hashes |
| `Cache.ConCache` | Wrapper around the ConCache library |
| `Cache.Sandbox` | Test adapter (auto-selected when `sandbox?: true`) |

### Adapter-specific functions

Some adapters inject extra functions via `__using__/1`:
- **`Cache.ETS`** — full set of ETS operations (`lookup/1`, `insert_raw/1`, `match_pattern/1`, `select/1`, `tab2list/0`, `update_counter/2`, etc.)
- **`Cache.Redis`** — hash and pipeline functions

## Sandbox Testing

When `sandbox?: true`, `Cache.Sandbox` adapter is used. Keys are prefixed with a sandbox ID from `Cache.SandboxRegistry` for per-test isolation.

Setup in `test/test_helper.exs`:
```elixir
Cache.SandboxRegistry.start_link()
ExUnit.start()
```

In test `setup`:
```elixir
Cache.SandboxRegistry.start([MyCache])
```

## Telemetry Events

- `[:elixir_cache, :cache, :put]` — span
- `[:elixir_cache, :cache, :get]` — span
- `[:elixir_cache, :cache, :get, :miss]` — counter on cache miss
- `[:elixir_cache, :cache, :delete]` — span
- `[:elixir_cache, :cache, :put, :error]` — counter on error
- `[:elixir_cache, :cache, :get, :error]` — counter on error
- `[:elixir_cache, :cache, :delete, :error]` — counter on error

All events include `%{cache_name: cache_name}` metadata.

## Adding a New Adapter

1. Create `lib/cache/my_adapter.ex`
2. Implement `@behaviour Cache` callbacks
3. Define `opts_definition/0` returning a NimbleOptions schema
4. Optionally export `__using__/1` to inject adapter-specific functions
5. Add tests in `test/cache/my_adapter_test.exs`
6. `Cache.ETS` is the simplest adapter to use as a reference
