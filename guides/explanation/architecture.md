# Architecture and Core Concepts

This document explains the key architectural concepts behind ElixirCache and how its components work together.

## Core Architecture

ElixirCache is designed around a simple principle: provide a consistent interface to different caching backends. The architecture consists of:

1. **Core Interface**: Defined by the `Cache` module
2. **Adapters**: Backend-specific implementations
3. **Strategy Adapters**: Higher-level patterns that compose over adapters
4. **Term Encoder**: Handles serialization and compression
5. **Telemetry Integration**: For observability and metrics
6. **Sandbox System**: For isolated testing

## The Cache Behaviour

At the heart of ElixirCache is the `Cache` behaviour, which defines the contract that all cache adapters must implement:

- `child_spec/1`: Defines how the cache is started and supervised
- `opts_definition/0`: Defines adapter-specific options
- `put/5`: Stores a value in the cache
- `get/3`: Retrieves a value from the cache
- `delete/3`: Removes a value from the cache

Each adapter implements these functions, allowing your application code to remain the same regardless of which cache backend you use.

## The `use Cache` Macro

When you `use Cache` in your module, the macro:

1. Sets up the configuration for your cache
2. Creates the required module functions that delegate to the appropriate adapter
3. Wraps operations in telemetry spans for metrics and observability
4. Implements the `get_or_create/2` convenience function
5. Adds sandboxing capabilities for testing if enabled

## Term Encoding and Compression

ElixirCache lets you store any Elixir term in any backend. How a term gets there depends on
what the backend can actually hold, and that is decided per adapter rather than globally.

Adapters that store Erlang terms natively — `Cache.ETS`, `Cache.Agent`, `Cache.PersistentTerm`,
`Cache.ConCache`, `Cache.Counter` — receive the term as-is. Serialising it first would cost a
`term_to_binary/1` on every write and a `binary_to_term/1` on every read while buying nothing,
and on a hot read path that decode dominates the lookup it is attached to.

Adapters that cannot hold a term serialise it with `:erlang.term_to_binary/1`:

- `Cache.Redis` stores bytes on the wire, so terms must be serialised before they leave the node.
- `Cache.DETS` owns a durable on-disk format, and so does `Cache.ETS` when configured with
  `:rehydration_path`. Both keep encoding so that files written by earlier versions stay readable.

Setting `:compression_level` forces encoding on any adapter — an explicit request to compress
is honoured even when the backend could have held the term directly.

Adapters declare this through the optional `c:Cache.native_term_storage?/1` callback. It is
resolved once at compile time, so there is no runtime branch on the read or write path.
The callback is optional and defaults to encoding, so third-party adapters are unaffected.

## Sandboxing for Tests

A unique feature of ElixirCache is its sandboxing capability for tests. When you enable sandboxing:

1. Each test has its own isolated cache namespace
2. Cache operations are automatically prefixed with a test-specific ID
3. Tests can run concurrently without cache interference or global overlap

This is achieved through the `Cache.SandboxRegistry` which maintains a registry of cache contexts.

## Adapters Design

Each adapter is designed to be a thin wrapper around the underlying storage mechanism:

### ETS Adapter

The ETS adapter uses Erlang Term Storage for high-performance in-memory caching. It:
- Starts an ETS table with the configured settings
- Provides direct access to ETS-specific functions
- Handles conversion between the Cache interface and ETS operations

### DETS Adapter

Similar to the ETS adapter but uses disk-based storage for persistence across restarts.

### Redis Adapter

The Redis adapter provides a more feature-rich distributed caching solution:
- Manages a connection pool to Redis
- Handles serialization of Elixir terms for Redis storage
- Provides access to Redis-specific operations like hash and JSON commands

### Agent Adapter

A simple implementation using Elixir's Agent for lightweight in-memory storage.

### ConCache Adapter

Wraps the ConCache library to provide its expiration and callback capabilities.

### PersistentTerm Adapter

Uses Erlang's `:persistent_term` storage for reads that require zero latency
and no process round-trips. Values are stored globally accessible without
locking. Write and delete operations are expensive (they copy the entire term
table internally), so this adapter is only suitable for data that changes
rarely, such as configuration or lookup tables. TTL is not supported.

### Counter Adapter

Uses Erlang's `:counters` module for lock-free atomic integer operations. The
counter array reference is stored in `:persistent_term`, giving every process
direct access without messaging overhead. The slot index for each key is
computed deterministically via `:erlang.phash2(key, size) + 1`, eliminating
any key-to-index bookkeeping and the race conditions that come with it. With a
small `initial_size`, distinct keys may hash to the same slot; increase
`initial_size` to reduce collision probability. Provides `increment/1,2` and
`decrement/1,2` in addition to the standard `Cache` interface.

## Strategy Adapters

Strategy adapters implement the `Cache.Strategy` behaviour and compose over
regular adapters to provide higher-level caching patterns. They are specified
using a tuple format: `adapter: {StrategyModule, UnderlyingAdapterOrConfig}`.

### Cache.HashRing

Distributes cache keys across Erlang cluster nodes using a consistent hash ring
powered by `libring`. Operations are forwarded to the owning node via
`:erpc.call/4`. The ring monitors node membership automatically.

### Cache.MultiLayer

Chains multiple cache modules together. Reads cascade fastest → slowest with
automatic backfill on slower-layer hits. Writes go slowest → fastest to ensure
durability before populating fast layers.

### Cache.RefreshAhead

Proactively refreshes values in the background before they expire. When a `get`
detects a value is within the refresh window, it returns the current value
immediately and spawns an async task to fetch a fresh one. Uses per-node ETS
deduplication and cross-node `:global` locking to prevent redundant refreshes.

## Telemetry Integration

ElixirCache provides telemetry events for all cache operations:
- `[:elixir_cache, :cache, :put]` - When storing values
- `[:elixir_cache, :cache, :get]` - When retrieving values
- `[:elixir_cache, :cache, :get, :miss]` - When a key is not found
- `[:elixir_cache, :cache, :delete]` - When deleting values
- Error events when operations fail

This allows you to monitor cache performance, hit/miss ratios, and error rates.
