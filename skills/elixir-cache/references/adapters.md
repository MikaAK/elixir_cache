# Cache Adapter Reference

## Table of Contents
- [ETS Adapter](#ets-adapter)
- [Redis Adapter](#redis-adapter)
- [ConCache Adapter](#concache-adapter)
- [PersistentTerm Adapter](#persistentterm-adapter)
- [Counter Adapter](#counter-adapter)
- [DETS Adapter](#dets-adapter)
- [Agent Adapter](#agent-adapter)
- [Sandbox Adapter](#sandbox-adapter)
- [Creating Custom Adapters](#creating-custom-adapters)

---

## ETS Adapter

High-performance in-memory cache using Erlang ETS tables.

### Options (NimbleOptions)

```elixir
use Cache, adapter: Cache.ETS, name: :fast, opts: [
  read_concurrency: true,       # concurrent reads (default false)
  write_concurrency: :auto,     # concurrent writes — true | false | :auto
  decentralized_counters: true, # use decentralized counters
  type: :set,                   # :set | :bag | :duplicate_bag (default :set)
  compressed: true,             # compress stored terms
  rehydration_path: "./cache"   # persist to disk, restore on restart
]
```

### ETS Rehydration

When `rehydration_path` is set:
- On startup, attempts to restore table from `<path>/<cache_name>.ets`
- On shutdown (SIGTERM, SIGHUP, SIGQUIT), writes table to disk via `tab2file`
- If the file has a different table name or is corrupt, a fresh table is created
- Useful for warm restarts without hitting the source of truth

### ETS Advanced Operations

The ETS adapter injects the full `:ets` API via `__using__/1`:

**Lookup and traversal:**
- `all/0`, `lookup/1`, `lookup_element/2`, `lookup_element/3` (OTP 26+)
- `member/1`, `first/0`, `last/0`, `next/1`, `prev/1`
- `first_lookup/0`, `last_lookup/0`, `next_lookup/1`, `prev_lookup/1` (OTP 26+)
- `tab2list/0`, `info/0`, `info/1`, `whereis/0`

**Pattern matching and selection:**
- `match_pattern/1`, `match_pattern/2`, `match_delete/1`
- `match_object/1`, `match_object/2`, `match/1`
- `match_spec_compile/1`, `match_spec_run/2`
- `select/1`, `select/2`, `select_count/1`, `select_delete/1`, `select_replace/1`
- `select_reverse/1`, `select_reverse/2`

**Mutation:**
- `insert_raw/1`, `insert_new/1`, `delete_object/1`, `delete_all_objects/0`, `delete_table/0`
- `update_counter/2`, `update_counter/3`, `update_element/2`, `update_element/3` (OTP 26+)
- `take/1`, `rename/1`, `give_away/2`, `setopts/1`

**Folding:**
- `foldl/2`, `foldr/2`

**Persistence:**
- `tab2file/1`, `tab2file/2`, `tabfile_info/1`, `file2tab/1`, `file2tab/2`
- `to_dets/1`, `from_dets/1`

**Other:**
- `table/0`, `table/1`, `slot/1`
- `safe_fixtable/1`, `init_table/1`, `repair_continuation/2`, `test_ms/2`, `is_compiled_ms/1`

### ETS Error Handling

The ETS adapter rescues exceptions in `get/3`, `put/5`, and `delete/3`, returning `{:error, ErrorMessage.internal_server_error(...)}` instead of crashing.

### ETS Examples

```elixir
MyCache.info(:size)                       # tuple count
MyCache.lookup("user:42")                 # raw ETS lookup
MyCache.match_pattern({:"$1", :_})        # pattern matching
MyCache.update_counter("views", {2, 1})   # atomic increment
MyCache.tab2file("backup.ets")            # persist to file
MyCache.member("key")                     # check existence
MyCache.delete_all_objects()              # clear table
```

---

## Redis Adapter

Distributed cache using Redix + Poolboy connection pool.

### Options (NimbleOptions)

```elixir
use Cache, adapter: Cache.Redis, name: :shared, opts: [
  uri: "redis://localhost:6379",  # connection URI (required)
  size: 10,                       # pool workers (default 50)
  max_overflow: 5,                # overflow workers (default 20)
  strategy: :fifo,                # pool strategy :fifo | :lifo (default :fifo)
  compression_level: 6            # zlib compression 1-9 (optional)
]
```

### TTL Handling

Redis TTL is converted from milliseconds to seconds via `round(ms / 1000)`. When TTL is `nil`, no expiry is set. When value is `nil`, the key is deleted (DEL command).

### Redis Sub-modules

The Redis adapter delegates to specialized sub-modules:

**Cache.Redis.Global** — core Redis commands:
- `command/3`, `command!/3` — execute single Redis command
- `pipeline/3`, `pipeline!/3` — execute command pipeline
- `scan/3` — scan keys with pattern matching

**Cache.Redis.Hash** — hash operations:
- `hash_get/4`, `hash_get_all/3`, `hash_get_many/3`
- `hash_set/6`, `hash_set_many/4`
- `hash_delete/4`, `hash_values/3`
- `hash_scan/4` — scan hash fields

**Cache.Redis.JSON** — RedisJSON operations:
- `get/4` (as `json_get`), `set/5` (as `json_set`)
- `delete/4` (as `json_delete`), `incr/5` (as `json_incr`)
- `clear/4` (as `json_clear`), `array_append/5` (as `json_array_append`)

**Cache.Redis.Set** — set operations:
- `sadd/4`, `smembers/3`

### Redis Key Namespacing

All keys are namespaced with the pool name: `"#{pool_name}:#{key}"` via `Redis.Global.cache_key/2`.

### Redis Hash Pattern

Common pattern for structured data under one key:

```elixir
defmodule LastSymbolPriceCache do
  use Cache,
    adapter: Cache.Redis,
    name: :last_symbol_price_cache,
    sandbox?: Mix.env() === :test,
    opts: :last_symbol_price_cache  # runtime config

  @default_ttl_ms :timer.hours(24) * 7

  def get_price(symbol, date \\ Date.utc_today()) do
    case hash_get(date_key(date), symbol) do
      {:ok, %LastPrice{} = price} -> {:ok, price}
      {:ok, nil} -> {:error, ErrorMessage.not_found("No price for #{symbol} on #{date}")}
      {:error, _} = err -> err
    end
  end

  def set_price(%LastPrice{symbol: symbol} = price, ttl \\ @default_ttl_ms) do
    hash_set(date_key(price.date), symbol, price, ttl)
  end

  defp date_key(date), do: "prices:#{date}"
end
```

---

## ConCache Adapter

TTL-based cache with locking `get_or_store` to prevent thundering herd. Backed by ETS internally.

### Options (NimbleOptions)

```elixir
use Cache, adapter: Cache.ConCache, name: :con, opts: [
  global_ttl: :timer.minutes(10),        # default :timer.minutes(30), or :infinity
  touch_on_read: true,                    # refresh TTL on reads (default false)
  acquire_lock_timeout: 3000,            # lock timeout ms (default 5000)
  ttl_check_interval: :timer.minutes(1), # TTL cleanup interval (default 1 min, false to disable)
  dirty?: true,                          # use dirty_put (no lock on put, default true)
  ets_options: [read_concurrency: true]  # passed to underlying ETS table
]
```

### Injected Functions

ConCache injects via `__using__/1`:
- `get_or_store(key, ttl, store_fun)` — locking get-or-create (prevents thundering herd)
- `dirty_get_or_store(key, store_fun)` — non-locking get-or-create

### Locking get-or-create

`get_or_store` acquires a per-key lock so only one process runs `store_fun`. Other processes waiting for the same key block until the first caller finishes, then read from cache:

```elixir
MyCache.get_or_store("key", :timer.seconds(60), fn -> expensive_compute() end)
```

### dirty? Mode

When `dirty?: true` (default), `put` uses `ConCache.dirty_put` (no lock acquisition). When `dirty?: false`, `put` uses `ConCache.put` (acquires a lock). The `dirty?` flag only affects `put` — `get_or_store` always uses locking.

---

## PersistentTerm Adapter

Zero-latency reads for rarely-written data using Erlang's `:persistent_term`.

### Options

```elixir
use Cache, adapter: Cache.PersistentTerm, name: :config, opts: []
```

### Key Characteristics

- **No TTL support** — values persist until explicitly deleted
- **Extremely fast reads** — no process message passing, no ETS lookup
- **Expensive writes and deletes** — triggers a global GC of all persistent terms
- **Best for**: feature flags, configuration, lookup tables that change rarely
- **Not suitable for**: high-write workloads, per-request caching

### Storage

Values stored as `:persistent_term.put({cache_name, key}, value)`. Retrieved with `:persistent_term.get({cache_name, key}, nil)`.

---

## Counter Adapter

Lock-free atomic integer counters backed by Erlang `:counters` module. Counter reference stored in `:persistent_term` for zero-overhead access.

### Options

```elixir
use Cache, adapter: Cache.Counter, name: :metrics, opts: [
  initial_size: 32,          # pre-allocated counter slots (default 1)
  write_concurrency: true    # concurrent writes to different slots (default false)
]
```

### Key-to-Slot Mapping

- **Integer key** — used directly as 0-based slot index (internally `key + 1` since `:counters` is 1-based)
- **Atom/String key** — hashed via `:erlang.phash2(key, size) + 1`

### API Semantics

| Function | Accepts | Behavior |
|----------|---------|----------|
| `increment(key, step \\ 1)` | any key type, any positive step | Atomic add |
| `decrement(key, step \\ 1)` | any key type, any positive step | Atomic subtract |
| `put(key, value)` | value must be `1` or `-1` only | Single increment/decrement |
| `get(key)` | **non-negative integer only** | Returns `{:ok, count}` or `{:ok, nil}` if zero |
| `delete(key)` | any key type | Zeroes the slot |

### Hash Collision Warning

With small `initial_size`, distinct atom/string keys may map to the same counter slot. Operations on colliding keys are summed in that shared slot. Increase `initial_size` to reduce collision probability. `delete` zeroes the entire slot, affecting all keys that hash to it.

---

## DETS Adapter

Disk-persisted cache using Erlang DETS tables. Survives VM restarts.

### Options (NimbleOptions)

```elixir
use Cache, adapter: Cache.DETS, name: :persistent, opts: [
  file_path: "./data",       # directory or file path (default "./")
  type: :set,                # :set | :bag | :duplicate_bag (default :set)
  ram_file: false            # enable RAM file (default false)
]
```

If `file_path` is a directory, the file is created as `<dir>/<cache_name>.dets`. The directory is auto-created if it doesn't exist.

### DETS Advanced Operations

The DETS adapter injects DETS-specific functions via `__using__/1`:

- `all/0`, `lookup/1`, `member/1`, `first/0`, `next/1`
- `match/1`, `match/2`, `match_object/1`, `match_object/2`, `match_delete/1`
- `select/1`, `select/2`, `select_delete/1`
- `insert_raw/1`, `insert_new/1`, `delete_all_objects/0`, `delete_object/1`
- `update_counter/2`, `foldl/2`, `foldr/2`, `traverse/1`
- `info/0`, `info/1`, `table/0`, `table/1`, `slot/1`
- `open_file/1`, `open_file/2`, `close/0`, `sync/0`
- `safe_fixtable/1`, `init_table/1`, `init_table/2`
- `bchunk/1`, `is_compatible_bchunk_format/1`, `is_dets_file/1`
- `repair_continuation/2`, `pid2name/1`
- `to_ets/1`, `from_ets/1`

### DETS TTL

DETS does **not** support TTL — the `ttl` parameter is ignored. Values persist until explicitly deleted or the file is removed.

---

## Agent Adapter

Simple agent-based cache for development and testing.

```elixir
use Cache, adapter: Cache.Agent, name: :simple, opts: []
```

---

## Sandbox Adapter

Test adapter auto-selected when `sandbox?: true`. Uses a simple Agent cache unique to the root process. Keys are prefixed with a sandbox ID from `Cache.SandboxRegistry` for per-test isolation.

Not used directly — enabled by setting `sandbox?: Mix.env() === :test` on any cache module.

---

## Creating Custom Adapters

1. Create `lib/cache/my_adapter.ex`
2. Implement `@behaviour Cache` callbacks:
   - `opts_definition/0` — NimbleOptions schema
   - `child_spec/1` — receives `{cache_name, cache_opts}`
   - `start_link/1` — receives resolved opts
   - `put/5` — `(cache_name, key, ttl, value, opts)`
   - `get/3` — `(cache_name, key, opts)`
   - `delete/3` — `(cache_name, key, opts)`
3. Optionally export `__using__/1` macro to inject adapter-specific functions
4. Add tests in `test/cache/my_adapter_test.exs`
5. `Cache.ETS` is the simplest adapter to use as a reference
