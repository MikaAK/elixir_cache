# 0.5.0

## Performance

- perf: values are no longer run through `:erlang.term_to_binary/1` for adapters that store Erlang terms natively (`Cache.ETS`, `Cache.Agent`, `Cache.PersistentTerm`, `Cache.ConCache`, `Cache.Counter`). The encode/decode round trip was pure overhead on those adapters, and the decode dominated the lookup it was attached to. On a 500k-entry ETS table, `get/1` of a ~10KB body drops from **29,981 ns to 6,211 ns (4.8x)** and `put/2` from **23,542 ns to 10,804 ns (2.2x)**. The win holds across payload sizes — a small map goes from 2,105 ns to 302 ns (7.0x).
- `Cache.PersistentTerm` now hands out the stored term itself on every read, restoring the zero-copy property the adapter exists for.

## Features

- feat: added the optional `c:Cache.native_term_storage?/1` callback, letting an adapter declare that it stores Erlang terms natively. It is resolved at compile time, so there is no runtime branch on the read or write path. The callback is optional and defaults to encoding, so third-party adapters keep their current behaviour unchanged.

## Bug Fixes

- fix: `Cache.ConCache.get_or_store/3` followed by `get/1` no longer raises. `get_or_store/3` writes through ConCache directly, bypassing the encode in `put/3`, so the matching `get/1` tried to `binary_to_term/1` a raw term.
- fix: a binary value wrapped in braces but not valid JSON (eg `"{oops}"`) no longer raises `Jason.DecodeError` on read. `Cache.TermEncoder.decode/1` used `Jason.decode!/1`, and now falls back to returning the binary unchanged.
- fix: raw `Cache.ETS` operations (`match_object/1`, `select/1`, `tab2list/0`, `foldl/2`) now see the terms that were `put`, rather than the opaque encoded binaries they used to return.

## Breaking Changes

- Values held by native-term adapters are now stored as terms rather than encoded binaries. This is not observable through `get/1`, `put/3` and `delete/1`, which round-trip exactly as before. It is observable if you read the underlying store directly (`:ets.lookup/2`, `:persistent_term.get/1`, `ConCache.get/2`) or through the raw ETS API — those now return terms, which is what they were always meant to return.
- `Cache.DETS` is unchanged and still encodes, so existing `.dets` files stay readable. `Cache.ETS` with `:rehydration_path` also still encodes, so existing table dumps stay loadable.
- An in-memory cache populated by an older version and read by this one would return raw binaries, but ETS, Agent, PersistentTerm and ConCache do not survive a restart, so there is no upgrade path on which that can happen.

# 0.4.9

## Performance

- perf(sandbox): make `Cache.SandboxRegistry.register_caches/2` post-register sleep configurable via `Cache.Config.sandbox_sleep_ms/0` (`config :elixir_cache, :sandbox_sleep_ms, 50`). Default is unchanged (50 ms). Test suites that don't need the sleep can set it to `0` in `config/test.exs` to save ~50 ms per cache registered per test — material on apps with many cache modules.

# 0.4.8

## Bug Fixes

- fix: ETS/DETS/Counter `start_link` now waits for the table/counter ref to be ready before returning, eliminating a startup race where supervisors saw a started child before the underlying table existed
- fix(sandbox): match real ETS match-spec semantics via `:ets.match_spec_compile/1` + `:ets.match_spec_run/2` in `select/2,3`, `select_count/2`, `select_delete/2`, and `select_replace/2`

## Chores

- ci: run workflows on `pull_request`; restrict `push` trigger to `main` to avoid duplicate runs

# 0.4.7

## Bug Fixes

- fix: apply `maybe_sandbox_key` to `hash_get_many` keys
- fix: support `sandbox?` option with strategy adapters (`HashRing`, `MultiLayer`, `RefreshAhead`)
- fix: isolate `Cache.Sandbox` scan results per sandbox

## Refactors

- refactor: scope `Cache.Sandbox` state by `sandbox_id` internally
- chore(metrics): fix cardinality leak in `extract_error_metadata/1`

# 0.4.6
# 0.4.5
- chore: fix dialyzer

# 0.4.4

## Bug Fixes

- refactor(counter): restrict `get/2` to integer keys only and add bounds checking

# 0.4.3

## Features

- feat(counter): add direct integer key indexing for deterministic slot access

# 0.4.2

## Refactors

- refactor(counter): replace dynamic index map with deterministic hash-based indexing

# 0.4.1

## New Adapters

- **`Cache.PersistentTerm`** — new adapter backed by Erlang's `:persistent_term` for
  extremely fast reads on rarely-written data such as configuration values. TTL is not
  supported; values persist until explicitly deleted.
- **`Cache.Counter`** — new atomic integer counter adapter backed by Erlang's `:counters`
  module. Provides lock-free increment/decrement operations via `put/4` (values `1` or
  `-1`) and injects `increment/1,2` and `decrement/1,2` into consumer modules through
  `use Cache`. Counter references and index maps are stored in `:persistent_term` for
  zero-latency access from any process.

## Strategy Adapters

- **`Cache.Strategy`** — new behaviour for strategy-based adapters. Strategies compose
  over existing cache adapters and receive the underlying adapter module and its resolved
  opts so they can delegate operations appropriately. Adapter tuple format:
  `adapter: {StrategyModule, UnderlyingAdapterOrConfig}`.
- **`Cache.HashRing`** — consistent hash ring strategy using `libring`. Distributes keys
  across Erlang cluster nodes, forwarding operations to the owning node via `:erpc` (or a
  configurable `rpc_module`). The ring tracks node membership automatically via
  `HashRing.Managed` with `monitor_nodes: true`. Includes **read-repair**: on a miss,
  previous ring snapshots (maintained by `Cache.HashRing.RingMonitor`) are consulted to
  lazily migrate keys after rebalancing. Configurable options: `ring_opts`,
  `node_weight`, `rpc_module`, `ring_history_size`.
- **`Cache.MultiLayer`** — cascades reads and writes through multiple cache layers (e.g.
  ETS → Redis). Reads walk fastest → slowest with automatic backfill on a slower-layer
  hit. Writes go slowest → fastest to ensure durability. Supports an optional `on_fetch`
  callback on total miss and a `backfill_ttl` for backfilled entries.
- **`Cache.RefreshAhead`** — proactively refreshes hot keys in the background before
  their TTL expires. On `get`, if the value is within the `refresh_before` window, the
  current value is returned immediately and an async `Task` refreshes it. Uses a per-cache
  ETS deduplication table and `:global` distributed locking to prevent redundant refreshes
  across nodes. Requires a `refresh_before` (ms) opt and a `refresh/1` callback or
  `on_refresh` opt.

## Test Utilities

- **`Cache.CaseTemplate`** — new ExUnit case template for applications with many test
  files. Define a `CacheCase` module once with `default_caches` or `supervisors`, then
  `use MyApp.CacheCase` in any test file to get automatic sandboxed cache setup. Supports
  per-file additional caches via `:caches` and detects duplicate cache registrations at
  setup time.

## Bug Fixes

- fix(ets): suppress `no_warn_undefined` for OTP 26+ ETS functions on older OTP versions.

# 0.4.0
feat: add all ets/dets functions and ability for ets to rehydrate
fix(con cache): allow concache to accept ets options

# 0.3.13
- fix: allow `Cache.ConCache` to accept `ets_options` (strict NimbleOptions validation + normalization)
- feat: allow `Cache.ETS` `write_concurrency: :auto` (OTP 25+)

# 0.3.12
- chore: fix warnings

# 0.3.11
- fix: redis

# 0.3.10
- fix: sandbox fix for smembers & sadd

# 0.3.9
- chore: add docs
- fix: set fix

# 0.3.8
- feat: add functions for ets & dets caches

# 0.3.7
- feat: add metrics module

# 0.3.6
- chore: fix child_spec type

# 0.3.5
- fix: Cache child spec for starting under a supervisor

# 0.3.4
- add `get_or_create(key, (() -> {:ok, value} | {:error, reson}))` to allow for create or updates

# 0.3.3
- use adapter options to allow for runtime options
- update sandbox hash_set_many behaviour to be consistent
- ensure dets does a mkdir_p at startup incase directory doesn't exist

# 0.3.2
- Update nimble options to 1.x

# 0.3.1
- add some more json sandboxing
- update redis to remove uri from command options

# 0.3.0
- add con_cache
- add ets cache
- fix hash opts for redis

# 0.2.1
- Adds support for application configuration and runtime options

# 0.2.0
- Stop redis connection errors from crashing the app
- Fix hash functions for `Cache.Redis`
- Support runtime cache config
- Support redis JSON
- Add `strategy` option to `Cache.Redis` for poolboy

# 0.1.1
- Expose `pipeline` and `command` functions on redis adapters

# 0.1.0
- Initial Release
