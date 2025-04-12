# Basic Cache Operations

This tutorial demonstrates the fundamental operations you can perform with ElixirCache.

## Setting Up a Cache Module

Before we begin with operations, make sure you have a cache module set up:

```elixir
defmodule MyApp.Cache do
  use Cache,
    adapter: Cache.ETS,
    name: :my_app_cache
end
```

## Basic Operations

### Storing Values

To store a value in the cache:

```elixir
# Basic storage with no TTL (Time To Live)
MyApp.Cache.put("user:1", %{name: "John", role: "admin"})

# With a TTL of 60 seconds
MyApp.Cache.put("session:123", %{user_id: 1, authenticated: true}, 60)
```

### Retrieving Values

To retrieve a value from the cache:

```elixir
case MyApp.Cache.get("user:1") do
  {:ok, user} ->
    IO.puts("Found user: #{user.name}")
    
  {:ok, nil} ->
    IO.puts("User not found in cache")
    
  {:error, reason} ->
    IO.puts("Error retrieving from cache: #{reason}")
end
```

### Deleting Values

To remove a value from the cache:

```elixir
MyApp.Cache.delete("user:1")
```

### Get or Create Pattern

A common pattern is to check if a value exists in the cache, and if not, create it:

```elixir
{:ok, user} = MyApp.Cache.get_or_create("user:1", fn ->
  # This function will only run if the key doesn't exist in the cache
  {:ok, %{name: "John", role: "admin"}}
end)
```

## Working with Complex Data

ElixirCache automatically handles serialization and deserialization of complex Elixir data structures, including:

- Maps
- Structs
- Lists
- Tuples
- Custom types

You can store these types without any additional configuration:

```elixir
# Storing a complex nested structure
data = %{
  users: [
    %{id: 1, name: "Alice", roles: [:admin, :editor]},
    %{id: 2, name: "Bob", roles: [:viewer]}
  ],
  settings: %{
    notifications: true,
    theme: "dark"
  }
}

MyApp.Cache.put("app:state", data)

# Later retrieve it with the same structure
{:ok, retrieved_data} = MyApp.Cache.get("app:state")
```

## Next Steps

Now that you understand the basic operations, you might want to explore:

- [Advanced cache techniques](advanced_techniques.md)
- [Working with different adapters](../how-to/choosing_adapter.md)
- [Using Redis with ElixirCache](../how-to/redis_setup.md)
