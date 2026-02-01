# How to Choose the Right Cache Adapter

ElixirCache supports multiple cache adapters, each with its own strengths and use cases. This guide will help you choose the most appropriate adapter for your specific needs.

## Available Adapters

ElixirCache provides the following adapters:

1. `Cache.ETS` - Erlang Term Storage
2. `Cache.DETS` - Disk-based ETS
3. `Cache.Redis` - Redis-backed distributed cache
4. `Cache.Agent` - Simple Agent-based in-memory cache
5. `Cache.ConCache` - ConCache wrapper
6. `Cache.Sandbox` - Isolated cache for testing

## Choosing an Adapter

### Cache.ETS

**Best for:**
- High-performance in-memory caching
- Single node applications
- Low-latency requirements

**Configuration example:**

```elixir
defmodule MyApp.Cache do
  use Cache,
    adapter: Cache.ETS,
    name: :my_app_cache,
    opts: [
      read_concurrency: true,
      write_concurrency: true
    ]
end
```

### Cache.DETS

**Best for:**
- Persistent caching across application restarts
- Larger datasets that shouldn't be lost on restart
- Less frequent access patterns

**Configuration example:**

```elixir
defmodule MyApp.PersistentCache do
  use Cache,
    adapter: Cache.DETS,
    name: :my_app_persistent_cache,
    opts: [
      file_path: "./cache_data"
    ]
end
```

### Cache.Redis

**Best for:**
- Distributed applications running on multiple nodes
- Systems requiring shared cache across services
- Applications needing advanced features like expiration, pub/sub, etc.

**Configuration example:**

```elixir
defmodule MyApp.DistributedCache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_redis_cache,
    opts: [
      uri: "redis://localhost:6379",
      size: 5,
      max_overflow: 2
    ]
end
```

### Cache.Agent

**Best for:**
- Simple use cases
- Small applications
- Development environments

**Configuration example:**

```elixir
defmodule MyApp.SimpleCache do
  use Cache,
    adapter: Cache.Agent,
    name: :my_app_simple_cache
end
```

### Cache.ConCache

**Best for:**
- Applications already using ConCache
- Needs for automatic key expiration and callback execution

**Configuration example:**

```elixir
defmodule MyApp.ConCache do
  use Cache,
    adapter: Cache.ConCache,
    name: :my_app_con_cache,
    opts: [
      ttl_check_interval: :timer.seconds(1),
      global_ttl: :timer.minutes(10)
    ]
end
```

### Cache.Sandbox

**Best for:**
- Testing environments
- Isolated tests that shouldn't interfere with each other

**Configuration example:**

```elixir
defmodule MyApp.TestCache do
  use Cache,
    adapter: Cache.ETS,
    name: :my_app_test_cache,
    sandbox?: true
end
```

## Switching Between Adapters

One of the main benefits of ElixirCache is the ability to easily switch between adapters without changing your application code. You can use different adapters in different environments:

```elixir
defmodule MyApp.Cache do
  use Cache,
    adapter: get_adapter(),
    name: :my_app_cache,
    opts: get_opts()

  defp get_adapter do
    case Mix.env() do
      :test -> Cache.Sandbox
      :dev -> Cache.ETS
      :prod -> Cache.Redis
    end
  end

  defp get_opts do
    case Mix.env() do
      :test -> []
      :dev -> [read_concurrency: true]
      :prod -> [
        uri: System.get_env("REDIS_URL", "redis://localhost:6379"),
        size: 10,
        max_overflow: 5
      ]
    end
  end
end
```

## Performance Considerations

When choosing an adapter, consider:

1. **Access patterns** - How frequently are you reading vs writing?
2. **Data volume** - How much data will be stored?
3. **Persistence requirements** - Does the data need to survive restarts?
4. **Distribution needs** - Will multiple nodes/services need access?
5. **Complexity** - Do you need advanced features or simple key-value storage?

Always benchmark different options with your specific workload to determine the best fit.
