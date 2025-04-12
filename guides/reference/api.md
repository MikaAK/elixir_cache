# API Reference

This document provides a comprehensive overview of the ElixirCache API and all available functions.

## Core Cache API

These functions are available on any cache module that uses the `Cache` behavior.

### put/3

```elixir
put(key, value)
put(key, ttl, value)
```

Stores a value in the cache.

- `key` - The key under which to store the value (atom or string)
- `ttl` - Optional time-to-live in seconds (integer)
- `value` - The value to store (any Elixir term)

Returns `:ok` or `{:error, reason}`.

### get/1

```elixir
get(key)
```

Retrieves a value from the cache.

- `key` - The key to look up (atom or string)

Returns `{:ok, value}`, `{:ok, nil}` if the key doesn't exist, or `{:error, reason}`.

### delete/1

```elixir
delete(key)
```

Removes a value from the cache.

- `key` - The key to delete (atom or string)

Returns `:ok` or `{:error, reason}`.

### get_or_create/2

```elixir
get_or_create(key, function)
```

Retrieves a value from the cache if it exists, or executes the provided function to create and store it.

- `key` - The key to look up or create (atom or string)
- `function` - A function that returns `{:ok, value}` or `{:error, reason}`

Returns `{:ok, value}` or `{:error, reason}`.

## Adapter-Specific Functions

### ETS Adapter

In addition to the core cache functions, ETS cache modules provide:

```elixir
match_object(pattern)
match_object(pattern, limit)
member(key)
select(match_spec)
select(match_spec, limit)
info()
info(item)
select_delete(match_spec)
match_delete(pattern)
update_counter(key, update_op)
insert_raw(data)
```

### DETS Adapter

DETS cache modules provide the same functions as ETS, plus:

```elixir
to_ets(ets_table)
from_ets(ets_table)
```

### Redis Adapter

Caches configured with the Redis adapter provide additional functionality beyond the standard cache operations. When you define a cache module using the Redis adapter, these functions become available on your cache module.

#### Additional Redis Operations

Below are the Redis-specific operations that your cache module will have available:

```elixir
# Define a cache module with the Redis adapter
defmodule MyApp.RedisCache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_redis_cache,
    opts: [uri: "redis://localhost:6379"]
end

# Hash operations
MyApp.RedisCache.hash_get("user:1", "name")                  # Get a hash field
MyApp.RedisCache.hash_get_all("user:1")                     # Get all fields in a hash
MyApp.RedisCache.hash_set("user:1", "email", "user@example.com") # Set a hash field
MyApp.RedisCache.hash_delete("user:1", "temporary_field")   # Delete a hash field

# JSON operations
MyApp.RedisCache.json_get("config")                         # Get entire JSON
MyApp.RedisCache.json_set("config", ".settings", %{theme: "dark"}) # Set JSON path
MyApp.RedisCache.json_incr("stats", ".counter")             # Increment value at path

# Direct Redis access
MyApp.RedisCache.command(["PING"])                          # Run a Redis command
MyApp.RedisCache.pipeline([["SET", "key1", "val1"], ["GET", "key2"]]) # Run commands in pipeline
```

#### Full List of Available Redis Functions

Your Redis cache module will include these functions:

* **Hash Functions**: `hash_get/2`, `hash_get_all/1`, `hash_get_many/1`, `hash_values/1`, `hash_set/3`, `hash_set/4`, `hash_set_many/2`, `hash_delete/2`, `hash_scan/1`, `hash_scan/2`

* **JSON Functions**: `json_get/1`, `json_get/2`, `json_set/3`, `json_delete/2`, `json_incr/2`, `json_incr/3`, `json_array_append/3`

* **Command Functions**: `command/1`, `command/2`, `command!/1`, `command!/2`, `pipeline/1`, `pipeline/2`, `pipeline!/1`, `pipeline!/2`, `scan/0`, `scan/1`

* **Set Functions**: `smembers/2`, `sadd/2`, `sadd/3`

## Telemetry Events

ElixirCache emits the following telemetry events:

| Event Name | Measurements | Metadata |
|------------|--------------|----------|
| `[:elixir_cache, :cache, :put]` | `%{}` | `%{cache_name: atom}` |
| `[:elixir_cache, :cache, :put, :error]` | `%{count: 1}` | `%{cache_name: atom, error: term}` |
| `[:elixir_cache, :cache, :get]` | `%{}` | `%{cache_name: atom}` |
| `[:elixir_cache, :cache, :get, :miss]` | `%{count: 1}` | `%{cache_name: atom}` |
| `[:elixir_cache, :cache, :get, :error]` | `%{count: 1}` | `%{cache_name: atom, error: term}` |
| `[:elixir_cache, :cache, :delete]` | `%{}` | `%{cache_name: atom}` |
| `[:elixir_cache, :cache, :delete, :error]` | `%{count: 1}` | `%{cache_name: atom, error: term}` |
