# Installation

This guide will walk you through the process of installing ElixirCache and setting up your first cache.

## Adding ElixirCache to Your Project

Add `:elixir_cache` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elixir_cache, "~> 0.3.8"}
  ]
end
```

Then run `mix deps.get` to fetch the dependency.

## Initial Setup

### Basic Setup with ETS Cache

To set up a basic ETS cache, create a module that uses the Cache macro:

```elixir
defmodule MyApp.Cache do
  use Cache,
    adapter: Cache.ETS,
    name: :my_app_cache
end
```

Then add the cache to your application's supervision tree in `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... other children
    MyApp.Cache
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Verifying Your Installation

To verify your cache is working, you can try storing and retrieving a value:

```elixir
# Store a value
MyApp.Cache.put("my_key", "Hello, ElixirCache!")

# Retrieve a value
{:ok, value} = MyApp.Cache.get("my_key")
IO.puts(value) # Outputs: Hello, ElixirCache!
```

## Next Steps

Once you have ElixirCache installed, you can:

- Learn about [basic cache operations](basic_operations.md)
- Explore [different adapter options](../how-to/choosing_adapter.md)
- Set up [Redis caching](../how-to/redis_setup.md) for distributed applications
