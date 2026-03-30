---
name: elixir-cache
description: >-
  Use when working with caching in any Elixir project that uses the elixir_cache library.
  TRIGGER on any of these scenarios:
  (1) Adding, modifying, or debugging any cache module (`use Cache`, `_cache` suffix modules, adapter selection);
  (2) Choosing between adapters (ETS vs Redis vs ConCache vs PersistentTerm vs Counter vs DETS vs Agent);
  (3) Redis operations — hash_get/hash_set/hash_scan, json_get/json_set, sadd/smembers, scan, command, pipeline, connection pools;
  (4) ETS operations — update_counter, match_pattern, tab2file, rehydration, read_concurrency;
  (5) Strategy adapters — MultiLayer (L1/L2 caching), HashRing (distributed/consistent hashing), RefreshAhead (proactive refresh);
  (6) Testing caches — Cache.CaseTemplate, SandboxRegistry, sandbox?, async test isolation, cache mocking;
  (7) Cache patterns — get_or_create, cache invalidation, cache warming, TTL management, compression_level;
  (8) Infrastructure — supervision tree setup with {Cache, [modules]}, runtime config, Poolboy pools;
  (9) Performance — thundering herd prevention (ConCache), lock-free counters, rate limiting with Cache.Counter;
  (10) Debugging — cache returning nil, sandbox not started, missing child_spec, telemetry/metrics.
  Also trigger when code imports or references: Cache, Cache.Redis, Cache.ETS, Cache.Counter,
  Cache.PersistentTerm, Cache.MultiLayer, Cache.HashRing, Cache.RefreshAhead, Cache.Sandbox,
  Cache.CaseTemplate, Cache.SandboxRegistry, Cache.Metrics, Cache.TermEncoder, Cache.Strategy.
  When in doubt about whether this skill applies, invoke it — it covers all caching concerns
  in projects using the elixir_cache library.
---

# ElixirCache Skill

## When to Use Which Adapter

| Need | Adapter | Why |
|------|---------|-----|
| Shared across cluster nodes | `Cache.Redis` | Distributed state via Redis |
| Single-node, high read throughput | `Cache.ETS` | Lock-free concurrent reads |
| Rarely-changed config data | `Cache.PersistentTerm` | Zero-latency reads, no TTL support |
| Atomic counters (rate limits, views) | `Cache.Counter` | Lock-free `:counters` module |
| Disk-persisted across restarts | `Cache.DETS` | Survives VM restarts |
| TTL + local locking (thundering herd) | `Cache.ConCache` | `get_or_store` with lock, `dirty?` mode |
| Simple in-process (dev/test) | `Cache.Agent` | Minimal overhead |
| L1 local + L2 distributed | `{Cache.MultiLayer, [...]}` | Fast reads, distributed writes |
| Consistent hash across cluster | `{Cache.HashRing, Adapter}` | Key affinity to node |
| Proactive refresh before expiry | `{Cache.RefreshAhead, Adapter}` | Hot cache, never stale |

**Default choice**: `Cache.ETS` for single-node, `Cache.Redis` for multi-node.

## Defining a Cache Module

```elixir
defmodule MyApp.UserCache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_user_cache,
    sandbox?: Mix.env() === :test,
    opts: [uri: "redis://localhost:6379"]
end
```

**Required:** `adapter`, `name`
**Optional:** `sandbox?` (use `Mix.env() === :test`), `opts`

## Starting in Supervision Tree

```elixir
# application.ex
children = [
  {Cache, [MyApp.UserCache, MyApp.SessionCache]}
]
```

## Basic Operations

```elixir
MyApp.UserCache.put("user:42", %{name: "Alice"})          # :ok
MyApp.UserCache.put("user:42", :timer.hours(1), %{name: "Alice"})  # :ok (with TTL)
MyApp.UserCache.get("user:42")                             # {:ok, %{name: "Alice"}} or {:ok, nil}
MyApp.UserCache.delete("user:42")                          # :ok
```

Values are automatically encoded/decoded via `Cache.TermEncoder` (binary term format with optional compression via `compression_level` opt).

## get_or_create

Fetch from cache or compute and store if missing:

```elixir
MyApp.UserCache.get_or_create("user:#{id}", fn ->
  case Accounts.find_user(%{id: id}) do
    nil -> {:error, ErrorMessage.not_found("User not found")}
    user -> {:ok, user}
  end
end)
```

The function must return `{:ok, value}` or `{:error, reason}`. On cache hit the function is never called.

## Runtime Configuration

Prefer runtime config over hardcoded opts to avoid secrets in code:

```elixir
# MFA tuple
use Cache, adapter: Cache.Redis, name: :my_cache, opts: {MyApp.Config, :redis_opts, []}

# Application env {app, key}
use Cache, adapter: Cache.Redis, name: :my_cache, opts: {:my_app, :redis_opts}

# Application env (module as key): Application.fetch_env!(:my_app, MyModule)
use Cache, adapter: Cache.Redis, name: :my_cache, opts: :my_app

# Zero-arity function
use Cache, adapter: Cache.Redis, name: :my_cache, opts: &MyApp.Config.redis_opts/0
```

## Strategy Adapters (Composition)

Strategy adapters wrap an underlying adapter to add higher-level behavior. They implement `Cache.Strategy` behaviour instead of `Cache` directly.

```elixir
# MultiLayer: ETS L1 + Redis L2
defmodule MyApp.LayeredCache do
  use Cache,
    adapter: {Cache.MultiLayer, [Cache.ETS, MyApp.RedisCache]},
    name: :layered_cache,
    sandbox?: Mix.env() === :test,
    opts: [backfill_ttl: :timer.seconds(30)]
end

# HashRing: consistent hashing across cluster
defmodule MyApp.DistributedCache do
  use Cache,
    adapter: {Cache.HashRing, Cache.ETS},
    name: :distributed_cache,
    sandbox?: Mix.env() === :test,
    opts: [read_concurrency: true]
end

# RefreshAhead: proactive background refresh
defmodule MyApp.HotCache do
  use Cache,
    adapter: {Cache.RefreshAhead, Cache.Redis},
    name: :hot_cache,
    sandbox?: Mix.env() === :test,
    opts: [uri: "redis://localhost", refresh_before: :timer.seconds(30)]

  def refresh(key) do
    {:ok, fetch_fresh_value(key)}
  end
end
```

For detailed strategy configuration and behavior, read `references/strategies.md`.

## Counter Adapter

For atomic increments without locks (backed by Erlang `:counters`):

```elixir
defmodule MyApp.MetricsCache do
  use Cache, adapter: Cache.Counter, name: :metrics_cache, opts: [initial_size: 32]
end

MyApp.MetricsCache.increment(:page_views)       # :ok (default step: 1)
MyApp.MetricsCache.increment(:page_views, 5)    # :ok (custom step)
MyApp.MetricsCache.decrement(:active_sessions)  # :ok
MyApp.MetricsCache.get(0)                       # {:ok, 42} or {:ok, nil} if zero
```

**Important Counter semantics:**
- `put/4` only accepts `1` or `-1` as values (acts as single increment/decrement)
- `increment/2` and `decrement/2` accept arbitrary step sizes
- `get/3` requires a **non-negative integer** key (slot index) — atom/string keys work for put/increment/decrement via hashing but not for get
- Keys hash to slots via `:erlang.phash2` — small `initial_size` causes collisions
- `delete/2` zeroes the slot, affecting all keys that hash to it

## Test Sandboxing

Sandboxed caches use `Cache.Sandbox` adapter per test PID. Fully async-safe.

```elixir
# test_helper.exs
Cache.SandboxRegistry.start_link()
ExUnit.start()

# Per-test setup
setup do
  Cache.SandboxRegistry.start([MyApp.UserCache, MyApp.PriceCache])
  :ok
end
```

### CaseTemplate (Recommended)

```elixir
# test/support/cache_case.ex
defmodule MyApp.CacheCase do
  use Cache.CaseTemplate, default_caches: [MyApp.UserCache, MyApp.PriceCache]
  # or auto-discover: use Cache.CaseTemplate, supervisors: [MyApp.Supervisor]
end

# In test files:
defmodule MyApp.PricingTest do
  use ExUnit.Case, async: true
  use MyApp.CacheCase
  # optionally: use MyApp.CacheCase, caches: [MyApp.ExtraCache]
end
```

CaseTemplate options:
- `:default_caches` — list of cache modules for every test
- `:supervisors` — discover caches from running supervisor's `{Cache, [...]}` child
- Per-test `:caches` — additional caches for one test file
- Per-test `:sleep` — ms to sleep after starting caches (default: 10)

## Redis Operations

Redis adapter injects hash, JSON, set, scan, and pipeline functions via `__using__/1`.

```elixir
# Hash operations
MyCache.hash_get("prices:2024-03-26", "AAPL")
MyCache.hash_set("prices:2024-03-26", "AAPL", price, :timer.hours(24))
MyCache.hash_get_all("prices:2024-03-26")
MyCache.hash_get_many([{"user:1", [:name, :email]}, {"user:2", [:name]}])
MyCache.hash_set_many([{"user:1", %{name: "Alice"}}, {"user:2", %{name: "Bob"}}])
MyCache.hash_delete("prices:2024-03-26", "AAPL")
MyCache.hash_values("prices:2024-03-26")
MyCache.hash_scan("prices:2024-03-26", match: "AAPL*", count: 50)

# JSON operations (requires RedisJSON)
MyCache.json_get("market:data", ["prices", "AAPL"])
MyCache.json_set("market:data", ["prices", "AAPL"], 150.25)
MyCache.json_incr("market:data", ["views"], 1)
MyCache.json_delete("market:data", ["prices", "OLD"])
MyCache.json_clear("market:data", ["temp"])
MyCache.json_array_append("market:data", ["symbols"], "TSLA")

# Set operations
MyCache.sadd("active:symbols", "AAPL")
MyCache.smembers("active:symbols", [])  # opts required, no default

# Raw commands and pipelines
MyCache.command(["PING"])
MyCache.pipeline([["GET", "k1"], ["GET", "k2"]])
MyCache.scan(match: "prices:*", type: "string", count: 100)
```

For detailed Redis adapter config and full API, read `references/adapters.md`.

## Telemetry

Cache operations auto-emit telemetry events. All events include `%{cache_name: cache_name}` metadata.

| Event | Type |
|-------|------|
| `[:elixir_cache, :cache, :put]` | span (start/stop with duration) |
| `[:elixir_cache, :cache, :get]` | span (start/stop with duration) |
| `[:elixir_cache, :cache, :get, :miss]` | counter (on `{:ok, nil}`) |
| `[:elixir_cache, :cache, :delete]` | span (start/stop with duration) |
| `[:elixir_cache, :cache, :put, :error]` | counter |
| `[:elixir_cache, :cache, :get, :error]` | counter |
| `[:elixir_cache, :cache, :delete, :error]` | counter |

If `prometheus_telemetry` is a dependency, `Cache.Metrics` is compiled with pre-configured metrics. Add to your metrics module:

```elixir
def metrics do
  Cache.Metrics.metrics() ++ [
    # your other metrics
  ]
end
```

## Common Mistakes

- Forgetting `sandbox?: Mix.env() === :test` — tests hit real Redis, break async safety
- Not calling `Cache.SandboxRegistry.start([caches])` per test — sandbox uninitialized, gets return `{:ok, nil}`
- Not starting `Cache.SandboxRegistry.start_link()` in test_helper — crash on first sandbox call
- Hardcoding host/port in `opts:` — use runtime config for deployments
- Using `Cache.ETS` for distributed data — ETS is node-local; use `Cache.Redis` or `Cache.HashRing`
- Omitting `{Cache, [MyModule]}` from supervision tree — cache process never starts
- Using `Cache.Counter.get/2` with atom/string key — get only accepts integer slot indices
- Using `Cache.PersistentTerm` for frequently-written data — writes trigger global GC

## Cache Invalidation Patterns

```elixir
# Direct invalidation after mutation
def update_user(user_id, attrs) do
  with {:ok, user} <- Repo.update(user, attrs) do
    MyApp.UserCache.delete("user:#{user_id}")
    {:ok, user}
  end
end

# PubSub-driven invalidation (multi-node)
def handle_info({:user_updated, user_id}, socket) do
  MyApp.UserCache.delete("user:#{user_id}")
  {:noreply, socket}
end
```

## Debugging Guide

| Symptom | Cause | Fix |
|---------|-------|-----|
| `{:ok, nil}` always returned | Sandbox not started | Add `Cache.SandboxRegistry.start([caches])` to test setup |
| `** (EXIT) no process` | Cache not in supervision tree | Add `{Cache, [MyCache]}` to children |
| `** (RuntimeError) Registry not started` | Missing SandboxRegistry | Add `Cache.SandboxRegistry.start_link()` to test_helper.exs |
| `** (NimbleOptions) unknown options` | Invalid adapter opts | Check adapter's `opts_definition/0` |
| Data visible in Redis but `get` returns nil | Key namespace mismatch | Keys are prefixed with `pool_name:` — check `cache_name` matches |
| Cache works in dev, fails in test | Missing `sandbox?: Mix.env() === :test` | Add sandbox option |
| Counter `get` returns error | Using atom/string key with `get` | `get` requires integer slot index |
| Stale data after node change | HashRing rebalancing | Read-repair handles this lazily on access |

## Cross-Skill Integration

- **Cache + Auth sessions**: Redis-backed `SessionToken` cache for token-to-user lookups
- **Cache + Oban workers**: Invalidate cache keys after background job mutations
- **Cache + PubSub**: Broadcast cache invalidation events across nodes for LiveView refetch
- **Cache + Testing**: Combine `Cache.CaseTemplate` with `DataCase` for DB + cache tests

```elixir
# Full test setup combining DB + cache
defmodule MyApp.IntegrationTest do
  use MyApp.DataCase, async: true
  use MyApp.CacheCase, caches: [MyApp.UserCache]
end
```

## Detailed References

- **Adapter configs** (ETS, Redis, ConCache, PersistentTerm, Counter, DETS, Agent): read `references/adapters.md`
- **Strategy configs** (MultiLayer, HashRing, RefreshAhead): read `references/strategies.md`
