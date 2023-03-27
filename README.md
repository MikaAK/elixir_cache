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

In our `application.ex`
```elixir
children = [
  {Cache, [MyModule]}
]
```

Now we can use `MyModule` to call various Cache apis

```elixir
MyModule.get("key") #> {:ok, nil}
MyModule.put("key", "value") #> :ok
MyModule.get("key") #> {:ok, "value"}
```

## Adapters
- `Cache.Agent` - Simple agent based caching
- `Cache.DETS`  - Disk persisted caching with [dets](https://www.erlang.org/doc/man/dets.html)
- `Cache.ETS`   - Super quick in-memory cache with [`ets`](https://www.erlang.org/doc/man/ets.html)
- `Cache.Redis` - Caching adapter using [Redix](https://github.com/whatyouhide/redix) & [Poolboy](https://github.com/devinus/poolboy), supports Redis JSON an Redis Hashes
- `Cache.ConCache` - Wrapper around [ConCache](https://github.com/sasa1977/con_cache) library

#### Adapter Specific Functions
Some adapters have specific functions such as redis which has hash functions and pipeline functions to make calls easier.

These adapter when used will add extra commands to your cache module.


## Sandboxing
Our cache config accepts a `sandbox?: boolean`. In sandbox mode, the `Cache.Sandbox` adapter will be used, which is just a simple Agent cache unique to the root process. The `Cache.SandboxRegistry` is responsible for registering test processes to a
unique instance of the Sandbox adapter cache. This makes it safe in test mode to run all your tests asynchronously!

For test isolation via the `Cache.SandboxRegistry` to work, you must start the registry in your setup, or your test_helper.exs:

```elixir
# test/test_helper.exs

+ Cache.SandboxRegistry.start_link()
ExUnit.start()

```

Then inside our `setup` for a test we can do:

```elixir
Cache.SandboxRegistry.start([MyCache, CacheItem])
```

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

## Runtime Configuration

Adapter configuration can also be specified at runtime. These options are first passed to the adapter
child_spec when starting the adapter and then passed to all runtime function calls.

For example:

```elixir
  # Configure with Module Function
  defmodule Cache.Example do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: {Cache.Example, :opts, []}

    def opts, do: [host: "localhost", port: 6379]
  end

  # Configure with callback function
  defmodule Cache.Example do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: &Cache.Example.opts/0

    def opts, do: [host: "localhost", port: 6379]
  end

  # Fetch from application config
  # config :elixir_cache, Cache.Example, []
  defmodule Cache.Example do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: :elixir_cache
  end

  # Fetch from application config
  # config :elixir_cache, :cache_opts, []
  defmodule Cache.Example do
    use Cache,
      adapter: Cache.Redis,
      name: :test_cache_redis,
      opts: {:elixir_cache, :cache_opts}
  end
```

Runtime options can be configured in one of the following formats:

* `{module, function, args}` - Module, function, args
* `{application_name, key}` - Application name. This is called as `Application.fetch_env!(application_name, key)`.
* `application_name` - Application name as an atom. This is called as `Application.fetch_env!(application_name, cache_module})`.
* `function` - Zero arity callback function. For eg. `&YourModule.options/0`
* `[key: value_type]` - Keyword list of options.
