# Architecture and Core Concepts

This document explains the key architectural concepts behind ElixirCache and how its components work together.

## Core Architecture

ElixirCache is designed around a simple principle: provide a consistent interface to different caching backends. The architecture consists of:

1. **Core Interface**: Defined by the `Cache` module
2. **Adapters**: Backend-specific implementations
3. **Term Encoder**: Handles serialization and compression
4. **Telemetry Integration**: For observability and metrics
5. **Sandbox System**: For isolated testing

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

ElixirCache includes internal term encoding functionality that handles serialization and deserialization of Elixir terms. This allows you to store complex Elixir data structures in any cache backend. The encoding system:

1. Uses Erlang's term_to_binary for efficient serialization
2. Applies configurable compression to reduce memory usage
3. Automatically handles decoding when retrieving values

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

## Telemetry Integration

ElixirCache provides telemetry events for all cache operations:
- `[:elixir_cache, :cache, :put]` - When storing values
- `[:elixir_cache, :cache, :get]` - When retrieving values
- `[:elixir_cache, :cache, :get, :miss]` - When a key is not found
- `[:elixir_cache, :cache, :delete]` - When deleting values
- Error events when operations fail

This allows you to monitor cache performance, hit/miss ratios, and error rates.
