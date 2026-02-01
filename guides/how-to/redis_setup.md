# How to Set Up Redis Caching

This guide walks you through configuring ElixirCache with Redis as the backend.

## Prerequisites

Before setting up Redis with ElixirCache, make sure you have:

1. Redis server installed and running
2. ElixirCache properly installed in your project

## Basic Redis Configuration

### Step 1: Define Your Redis Cache Module

Create a module that uses the Cache functionality with the Redis adapter:

```elixir
defmodule MyApp.RedisCache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_redis,
    opts: [
      uri: "redis://localhost:6379",
      size: 5,
      max_overflow: 2
    ]
end
```

### Step 2: Add to Your Supervision Tree

Make sure to add your Redis cache to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    # ... other children
    MyApp.RedisCache
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Redis Configuration Options

The Redis adapter supports various configuration options:

```elixir
defmodule MyApp.RedisCache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_redis,
    opts: [
      # Connection URI (required) - includes host, port, password, database
      uri: "redis://:your_password@redis.example.com:6379/0",
      
      # Connection pool settings
      size: 10,                   # Number of connections in the pool
      max_overflow: 5,            # Maximum number of overflow workers
      strategy: :fifo             # Queue strategy (:fifo or :lifo)
    ]
end
```

The Redis URI format supports authentication and database selection:
- `redis://localhost:6379` - Basic connection
- `redis://:password@localhost:6379` - With password
- `redis://:password@localhost:6379/1` - With password and database number

## Environment-Based Configuration

For better maintainability, consider using environment variables or configuration files:

```elixir
defmodule MyApp.RedisCache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_redis,
    opts: [
      uri: System.get_env("REDIS_URL", "redis://localhost:6379"),
      size: String.to_integer(System.get_env("REDIS_POOL_SIZE", "10")),
      max_overflow: String.to_integer(System.get_env("REDIS_MAX_OVERFLOW", "5"))
    ]
end
```

## Working with Redis-Specific Features

The Redis adapter provides some Redis-specific functionality beyond the standard cache interface:

### Hash Operations

```elixir
# Set hash field
MyApp.RedisCache.hash_set("user:1", "name", "John")
MyApp.RedisCache.hash_set("user:1", "email", "john@example.com")

# Get hash field
{:ok, name} = MyApp.RedisCache.hash_get("user:1", "name")

# Get all hash fields
{:ok, user_data} = MyApp.RedisCache.hash_get_all("user:1")

# Delete hash field
MyApp.RedisCache.hash_delete("user:1", "email")
```

### JSON Operations

```elixir
# Store JSON (path is optional, nil or omitted stores at root)
json_data = %{users: [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]}
MyApp.RedisCache.json_set("app:data", json_data)

# Get JSON (no path returns entire document)
{:ok, data} = MyApp.RedisCache.json_get("app:data")

# Get nested JSON path (path as list)
{:ok, users} = MyApp.RedisCache.json_get("app:data", ["users"])

# Update specific path (use list with index for arrays)
MyApp.RedisCache.json_set("app:data", ["users", 0, "name"], "Alicia")
```

## Troubleshooting Redis Connection

If you're having issues connecting to Redis:

1. **Verify Redis is running**: `redis-cli ping` should return `PONG`
2. **Check connection settings**: Ensure your Redis URI is correct (format: `redis://[:password@]host:port[/database]`)
3. **Network issues**: Ensure your application can reach the Redis server (firewalls, network rules)
4. **Authentication**: Confirm your Redis password is correct if authentication is enabled
5. **Connection pool**: Monitor your connection pool usage to ensure you haven't exhausted connections

## Redis in Production

For production environments, consider:

1. **Use a dedicated Redis instance** or managed Redis service
2. **Enable persistence** in Redis if you need data to survive restarts
3. **Configure appropriate timeouts** based on your application needs
4. **Monitor Redis performance** using tools like Prometheus and Grafana
5. **Set up proper SSL** if connecting to Redis over untrusted networks
