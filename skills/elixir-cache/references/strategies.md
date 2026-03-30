# Cache Strategy Adapter Reference

Strategy adapters compose over existing cache adapters to provide higher-level caching patterns. They implement `Cache.Strategy` behaviour (not `Cache`).

## Table of Contents
- [Strategy Behaviour](#strategy-behaviour)
- [MultiLayer](#multilayer)
- [HashRing](#hashring)
- [RefreshAhead](#refreshahead)

---

## Strategy Behaviour

```elixir
@callback opts_definition() :: Keyword.t()
@callback child_spec({cache_name, strategy_config, adapter_opts}) :: Supervisor.child_spec()
@callback get(cache_name, key, strategy_config, adapter_opts) :: ErrorMessage.t_res(any)
@callback put(cache_name, key, ttl, value, strategy_config, adapter_opts) :: :ok | ErrorMessage.t()
@callback delete(cache_name, key, strategy_config, adapter_opts) :: :ok | ErrorMessage.t()
```

Check if a module is a strategy: `Cache.Strategy.strategy?(module)`.

Usage: `adapter: {StrategyModule, config}` in `use Cache`.

---

## MultiLayer

Cascades through multiple cache layers (fastest to slowest reads, slowest to fastest writes).

### Configuration

```elixir
defmodule MyApp.LayeredCache do
  use Cache,
    adapter: {Cache.MultiLayer, [Cache.ETS, MyApp.RedisCache]},
    name: :layered_cache,
    sandbox?: Mix.env() === :test,
    opts: [
      backfill_ttl: :timer.seconds(30),
      on_fetch: &__MODULE__.fetch/1
    ]

  def fetch(key), do: {:ok, "value_for_#{key}"}
end
```

### Layer Types

Each element in the layer list can be:
- **A cache module** (already running, has `get/1` and `put/2`) — not supervised by MultiLayer
- **An adapter module** (e.g. `Cache.ETS`) — auto-started and supervised
- **`__MODULE__`** — positions the current module's own cache within the chain

If `__MODULE__` is omitted, the defining module acts as a pure facade with no local cache.

### Read Behavior

1. Layers iterated fastest to slowest (list order)
2. On a hit from layer N, value is **backfilled** into layers 1..N-1
3. Errors from a layer are treated as misses (continues to next layer)

### Write Behavior

1. Layers written **slowest to fastest** (reverse list order)
2. If a slow write fails, the write stops — prevents polluting faster layers with data that failed to persist

### Options

| Option | Type | Description |
|--------|------|-------------|
| `backfill_ttl` | `pos_integer \| nil` | TTL for backfilled entries (default: nil = no expiry) |
| `on_fetch` | `mfa \| fun/1` | Callback on total cache miss. Receives key, returns `{:ok, value}` or `{:error, reason}` |

### Fetch Callback

When all layers miss and `on_fetch` is set, the callback is invoked. On success, the value is backfilled into all layers.

---

## HashRing

Distributes cache keys across Erlang cluster nodes using consistent hashing via `libring`.

### Configuration

```elixir
defmodule MyApp.DistributedCache do
  use Cache,
    adapter: {Cache.HashRing, Cache.ETS},
    name: :distributed_cache,
    sandbox?: Mix.env() === :test,
    opts: [
      read_concurrency: true,
      node_weight: 256,
      ring_history_size: 5,
      rpc_module: :erpc,
      ring_opts: [
        node_blacklist: [~r/^remsh.*$/, ~r/^rem-.*$/],
        node_whitelist: []
      ]
    ]
end
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ring_opts` | keyword | `[]` | Passed to `HashRing.Worker` (`node_blacklist`, `node_whitelist`) |
| `node_weight` | pos_integer | `128` | Virtual nodes per physical node for distribution evenness |
| `rpc_module` | atom | `:erpc` | Module for remote calls (must implement `call/4`) |
| `ring_history_size` | pos_integer | `3` | Previous ring snapshots kept for read-repair |

### How It Works

1. Each node starts the same underlying adapter locally
2. Key is hashed to determine owning node via consistent ring
3. If owning node is `Node.self()`, operation executes locally
4. If remote, operation forwarded via `rpc_module` (default `:erpc`)

The ring auto-tracks node membership via `HashRing.Managed` with `monitor_nodes: true`.

### Read-Repair

When ring topology changes (node join/leave), keys may hash to different nodes. `Cache.HashRing.RingMonitor` handles migration:

1. Snapshots the ring before each change (keeps `ring_history_size` previous rings)
2. On a `get` miss from the current owning node, consults previous rings newest-first
3. For each previous ring where the key hashed to a different (live) node, attempts a `get`
4. On hit: returns value immediately, writes to current owner (migration), deletes from old node async

This lazily migrates hot keys without scanning the entire ring.

### Node Blacklist

By default, `remsh` and `rem-` prefixed nodes are blacklisted from the ring (remote shell nodes). Customize via `ring_opts: [node_blacklist: [...]]`.

### Sandbox Behavior

When `sandbox?: true`, the ring is bypassed entirely — all operations execute locally against the sandbox adapter.

### Supervision Tree

HashRing starts a supervisor with three children:
1. The underlying adapter's child spec
2. `HashRing.Worker` (managed ring)
3. `Cache.HashRing.RingMonitor` (ring change tracker)

---

## RefreshAhead

Proactively refreshes values before they expire. Values are stored with timestamps; on `get`, if the value is within the refresh window, the current value is returned immediately and an async `Task` refreshes it in the background.

### Configuration

```elixir
defmodule MyApp.HotCache do
  use Cache,
    adapter: {Cache.RefreshAhead, Cache.Redis},
    name: :hot_cache,
    sandbox?: Mix.env() === :test,
    opts: [
      uri: "redis://localhost:6379",
      refresh_before: :timer.seconds(30),
      on_refresh: &__MODULE__.refresh/1
    ]

  # Alternative: define refresh/1 on the module instead of on_refresh opt
  def refresh(key) do
    {:ok, fetch_fresh_value(key)}
  end
end
```

### Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `refresh_before` | pos_integer | yes | Milliseconds before TTL expiry to trigger background refresh |
| `on_refresh` | `mfa \| fun/1` | no | Refresh callback. If omitted, cache module must define `refresh/1` |
| `lock_node_whitelist` | `atom \| [atom]` | no | Node whitelist for distributed refresh locks (default: all connected) |

### How It Works

1. **`put`** wraps the value as `{value, inserted_at_ms, ttl_ms}` before delegating to the underlying adapter
2. **`get`** unwraps the tuple. If `now - inserted_at >= ttl - refresh_before`, spawns a background refresh
3. A per-cache **ETS deduplication table** (`:<name>_refresh_tracker`) prevents multiple concurrent refreshes for the same key
4. A **`:global.set_lock`** prevents duplicate refreshes across the cluster
5. On successful refresh, `put` is called with the new value and same TTL, resetting `inserted_at`

### Refresh Callback Resolution

The refresh callback is resolved in this order:
1. `on_refresh` option (MFA tuple or fun/1) if provided
2. `refresh/1` function on the cache module
3. Error if neither exists

### Deduplication

- **Local**: ETS `insert_new` on the tracker table ensures only one refresh task per key per node
- **Distributed**: `:global.set_lock` with configurable node whitelist prevents cross-node duplicate refreshes
- The tracker entry is cleaned up in an `after` block regardless of refresh success/failure

### Sandbox Behavior

When `sandbox?: true`, values are stored unwrapped. Refresh logic is bypassed entirely — no background tasks are spawned during tests.

### Supervision Tree

RefreshAhead starts a supervisor with two children:
1. The underlying adapter's child spec
2. The refresh tracker ETS table (via a hibernating Task)
