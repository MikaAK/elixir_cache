# ElixirCache
[![Hex version badge](https://img.shields.io/hexpm/v/elixir_cache.svg)](https://hex.pm/packages/elixir_cache)
[![Test](https://github.com/MikaAK/elixir_cache/actions/workflows/test.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/test.yml)
[![Credo](https://github.com/MikaAK/elixir_cache/actions/workflows/credo.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/credo.yml)
[![Dialyzer](https://github.com/MikaAK/elixir_cache/actions/workflows/dialyzer.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/dialyzer.yml)
[![Coverage](https://github.com/MikaAK/elixir_cache/actions/workflows/coverage.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/coverage.yml)

The goal of this project is to unify Cache APIs and make Strategies easy to implement and sharable
across all storage types/adapters

The second goal is to make sure testing of all cache related funciions is easy, meaning caches should be isolated
per test and not leak their state to outside tests

## Installation

The package can be installed by adding `elixir_cache` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elixir_cache, "~> 0.1.0"}
  ]
end
```

The docs can be found at <https://hexdocs.pm/elixir_cache>.


## Usage
```elixir
defmodule MyModule do
  use Cache,
    adapter: Cache.Redis,
    name: :my_name,
    sandbox?: Mix.env() === :test,
    opts: [...opts]
end
```

Now we can use `MyModule` to call various Cache apis

```elixir
MyModule.get("key") #> {:ok, nil}
MyModule.put("key", "value") #> :ok
MyModule.get("key") #> {:ok, "value"}
```

#### Adapter Specific Functions
Some adapters have specific functions such as redis which has hash functions and pipeline functions to make calls easier.

These adapter when used will add extra commands to your cache module.


## Sandboxing
Our cache config accepts a `sandbox?: boolean`, in sanbox mode, the `Cache.Sandbox` adapter will be used which is just a simple Agent cache which is unique to the root process. All subprocesses will also have access to the same cache but it will be isolated by root process. This means in test mode, each process has it's own cache and is isolated from other tests, allowing you to run all your tests asynchronously

## Creating Adapters
Adapters are very easy to create in this model and are basically just a module that implement the `@behaviour Cache`

This behaviour adds the following callbacks

```
put(cache_name, key, ttl, value, opts \\ [])
get(cache_name, key, opts \\ [])
delete(cache_name, key, opts \\ [])
opts_definition() # NimbleOptions definition map
child_spec({cache_name, cache_opts})
```

`Cache.ETS` is probably the easiest adapter to follow as a guide as it's a simple `Task`
