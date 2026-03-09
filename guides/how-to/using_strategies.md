# Using Strategy Adapters

Strategy adapters compose over existing cache adapters to provide higher-level
caching patterns. They are specified using a two-element tuple as the `adapter`
option:

```elixir
use Cache,
  adapter: {StrategyModule, UnderlyingAdapterOrConfig},
  name: :my_cache,
  opts: [strategy_opt: value, underlying_adapter_opt: value]
```

The `opts` keyword list is shared between the strategy and the underlying
adapter. Strategy-specific keys are validated and consumed by the strategy;
any remaining keys are passed through to the underlying adapter.

## Available Strategies

| Strategy | Use Case |
|---|---|
| `Cache.HashRing` | Distribute keys across Erlang cluster nodes via consistent hashing |
| `Cache.MultiLayer` | Cascade reads/writes through multiple cache layers (e.g. ETS → Redis) |
| `Cache.RefreshAhead` | Proactively refresh hot keys in the background before they expire |

---

## Cache.HashRing

Distributes cache keys across Erlang cluster nodes using a consistent hash ring
powered by [`libring`](https://hex.pm/packages/libring). Each key always hashes
to the same node (given the same ring), so no cross-node coordination is needed
for reads — the operation is simply forwarded to the owning node via a
configurable RPC module (defaults to `:erpc`).

### Usage

```elixir
defmodule MyApp.DistributedCache do
  use Cache,
    adapter: {Cache.HashRing, Cache.ETS},
    name: :distributed_cache,
    opts: [read_concurrency: true]
end
```

Start it in your supervision tree:

```elixir
children = [MyApp.DistributedCache]
Supervisor.start_link(children, strategy: :one_for_one)
```

### How It Works

1. Every node starts the same underlying adapter locally (e.g. an ETS table).
2. On `get`/`put`/`delete`, the key is hashed against the managed ring to pick
   the owning node.
3. If the owning node is `Node.self()`, the operation runs locally.
4. If it is a remote node, the operation is forwarded via the configured
   `rpc_module` (default `:erpc`).

The ring monitors node membership automatically (`monitor_nodes: true`), so
nodes joining or leaving the cluster are reflected without manual intervention.

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `ring_opts` | `keyword` | `[]` | Options passed to `HashRing.Worker`, such as `node_blacklist` and `node_whitelist`. |
| `node_weight` | `pos_integer` | `128` | Number of virtual nodes (shards) per node on the ring. Higher values give more even key distribution. |
| `rpc_module` | `atom` | `:erpc` | Module used for remote calls. Must implement `call/4` with the same signature as `:erpc.call/4`. |
| `ring_history_size` | `pos_integer` | `3` | Number of previous ring snapshots to retain for read-repair fallback. |

### Read-Repair

When a node joins or leaves the cluster, some keys will hash to a different
node. Rather than doing a full key migration scan, `Cache.HashRing` uses
**read-repair** to lazily migrate keys on demand:

1. A `get` call misses on the current owning node.
2. Previous ring snapshots are consulted in order (newest first), maintained
   by the `Cache.HashRing.RingMonitor` GenServer.
3. For each previous ring, if the key hashed to a different reachable node,
   a `get` is attempted there.
4. On a hit, the value is written to the current owner and the old node is
   deleted asynchronously.

Nodes that are unreachable are skipped automatically, and each node is only
tried once even if it appears in multiple historical ring snapshots.

To control how many previous rings are retained:

```elixir
opts: [ring_history_size: 5]
```

### Custom RPC Module

To use a different RPC library (e.g. for timeout control or tracing):

```elixir
opts: [rpc_module: MyApp.CustomRPC]
```

The module must export `call(node, module, function, args)`.

---

## Cache.MultiLayer

Chains multiple cache modules together. Reads walk the list fastest → slowest;
on a hit the value is backfilled into all faster layers. Writes go slowest →
fastest to ensure durability before populating fast layers.

### Usage

```elixir
defmodule MyApp.LayeredCache do
  use Cache,
    adapter: {Cache.MultiLayer, [MyApp.LocalCache, MyApp.RedisCache]},
    name: :layered_cache,
    opts: [backfill_ttl: :timer.minutes(5)]
end
```

Each element in the layers list must be a module that exposes `get/1`, `put/3`,
and `delete/1` — i.e. a module defined with `use Cache`.

### Fetch Callback on Total Miss

If all layers miss, an optional `on_fetch` callback can supply the value and
backfill all layers:

```elixir
defmodule MyApp.LayeredCache do
  use Cache,
    adapter: {Cache.MultiLayer, [MyApp.LocalCache, MyApp.RedisCache]},
    name: :layered_cache,
    opts: [on_fetch: &__MODULE__.fetch/1]

  def fetch(key) do
    {:ok, MyApp.Repo.get_value(key)}
  end
end
```

### Options

| Option | Type | Description |
|---|---|---|
| `on_fetch` | `fun/1` or MFA | Called on total miss. Receives `key`, returns `{:ok, value}` or `{:error, reason}`. |
| `backfill_ttl` | `pos_integer \| nil` | TTL used when backfilling layers on a slower-layer hit. Defaults to `nil` (no expiry). |

---

## Cache.RefreshAhead

Proactively refreshes values in the background before they expire. When a `get`
detects that a cached value is within the `refresh_before` window, it returns
the current (still-valid) value immediately and spawns an async `Task` to fetch
a fresh one. Only actively-read keys are refreshed — unread keys naturally expire.

### Usage

Define a `refresh/1` callback on your cache module:

```elixir
defmodule MyApp.Cache do
  use Cache,
    adapter: {Cache.RefreshAhead, Cache.Redis},
    name: :my_cache,
    opts: [
      uri: "redis://localhost:6379",
      refresh_before: :timer.seconds(30)
    ]

  def refresh(key) do
    {:ok, MyApp.fetch_value(key)}
  end
end
```

### Inline Refresh Callback

You can supply the callback directly via `on_refresh` instead of defining
`refresh/1`:

```elixir
opts: [
  refresh_before: :timer.seconds(30),
  on_refresh: fn key -> {:ok, MyApp.fetch_value(key)} end
]
```

### How the Refresh Window Works

Given a value stored with `ttl = 60_000` ms and `refresh_before = 10_000` ms:

- For the first 50 seconds, `get` returns the value with no background work.
- After 50 seconds, `get` returns the value **and** spawns a refresh task.
- The refresh task calls `refresh/1`, then writes the new value with the same TTL.
- A per-cache ETS deduplication table ensures only one refresh runs per key at
  a time.
- A `:global` lock prevents the same key from being refreshed on multiple nodes
  simultaneously when running in a cluster.

### Options

| Option | Type | Required | Description |
|---|---|---|---|
| `refresh_before` | `pos_integer` | Yes | Milliseconds before TTL expiry to trigger background refresh. |
| `on_refresh` | `fun/1` or MFA | No | Refresh callback. Falls back to `YourCacheModule.refresh/1`. |
| `lock_node_whitelist` | `atom` or `[atom]` | No | Node whitelist for distributed refresh locks. Defaults to all connected nodes. |

---

## Testing Strategies

Strategies respect the `sandbox?: true` option. When sandboxed, the strategy
layer is bypassed entirely and the `Cache.Sandbox` adapter is used directly,
giving you the same per-test isolation as regular adapters:

```elixir
defmodule MyApp.Cache do
  use Cache,
    adapter: {Cache.RefreshAhead, Cache.Redis},
    name: :my_cache,
    sandbox?: true,
    opts: [refresh_before: :timer.seconds(30)]
end
```

In your test setup:

```elixir
setup do
  Cache.SandboxRegistry.start(MyApp.Cache)
  :ok
end
```
