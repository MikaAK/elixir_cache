# ElixirCache
[![Hex version badge](https://img.shields.io/hexpm/v/elixir_cache.svg)](https://hex.pm/packages/elixir_cache)
[![Test](https://github.com/MikaAK/elixir_cache/actions/workflows/test.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/test.yml)
[![Credo](https://github.com/MikaAK/elixir_cache/actions/workflows/credo.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/credo.yml)
[![Dialyzer](https://github.com/MikaAK/elixir_cache/actions/workflows/dialyzer.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/dialyzer.yml)
[![Coverage](https://github.com/MikaAK/elixir_cache/actions/workflows/test.yml/badge.svg)](https://github.com/MikaAK/elixir_cache/actions/workflows/test.yml)

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
- `Cache.Redis` - Caching adapter using [Redix](https://github.com/whatyouhide/redix) & [Poolboy](https://github.com/devinus/poolboy), supports Redis JSON and Redis Hashes
- `Cache.ConCache` - Wrapper around [ConCache](https://github.com/sasa1977/con_cache) library
- `Cache.PersistentTerm` - Zero-latency reads for rarely-written data via Erlang's `:persistent_term`
- `Cache.Counter` - Lock-free atomic integer counters via Erlang's `:counters` module

#### Adapter Specific Functions
Some adapters have specific functions such as redis which has hash functions and pipeline functions to make calls easier.

These adapters when used will add extra commands to your cache module.

`Cache.Counter` adds `increment/1,2` and `decrement/1,2` to your module:

```elixir
defmodule MyApp.CounterCache do
  use Cache,
    adapter: Cache.Counter,
    name: :my_app_counter_cache,
    opts: []
end

MyApp.CounterCache.increment(:page_views)
MyApp.CounterCache.decrement(:active_users)
{:ok, count} = MyApp.CounterCache.get(:page_views)
```

## Strategy Adapters

Strategy adapters compose over existing adapters to provide higher-level caching patterns.
Use a two-element tuple as the `adapter` option:

```elixir
use Cache,
  adapter: {StrategyModule, UnderlyingAdapterOrConfig},
  name: :my_cache,
  opts: [strategy_opt: value, underlying_adapter_opt: value]
```

- `Cache.HashRing` - Distribute keys across Erlang cluster nodes via consistent hashing ([libring](https://hex.pm/packages/libring))
- `Cache.MultiLayer` - Cascade reads/writes through multiple cache layers (e.g. ETS → Redis) with automatic backfill
- `Cache.RefreshAhead` - Proactively refresh hot keys in the background before they expire

See the [Using Strategy Adapters](guides/how-to/using_strategies.md) guide for full details.


## Sandboxing
Our cache config accepts a `sandbox?: boolean`. In sandbox mode, the `Cache.Sandbox` adapter will be used, which is just a simple Agent cache unique to the root process. The `Cache.SandboxRegistry` is responsible for registering test processes to a
unique instance of the Sandbox adapter cache. This makes it safe in test mode to run all your tests asynchronously!

For test isolation via the `Cache.SandboxRegistry` to work, you must start the registry in your `test/test_helper.exs`:

```elixir
Cache.SandboxRegistry.start_link()
ExUnit.start()
```

Then inside a `setup` block:

```elixir
Cache.SandboxRegistry.start([MyCache, CacheItem])
```

### Cache.CaseTemplate

For applications with many test files, use `Cache.CaseTemplate` to define a single `CacheCase` module that automatically starts sandboxed caches in every test that uses it.

Create a `CacheCase` module in your test support directory:

```elixir
# test/support/cache_case.ex
defmodule MyApp.CacheCase do
  use Cache.CaseTemplate, default_caches: [MyApp.UserCache, MyApp.SessionCache]
end
```

Or discover caches automatically from a running supervisor:

```elixir
defmodule MyApp.CacheCase do
  use Cache.CaseTemplate, supervisors: [MyApp.Supervisor]
end
```

Then use it in any test file:

```elixir
defmodule MyApp.SomeTest do
  use ExUnit.Case, async: true
  use MyApp.CacheCase

  # optionally add extra caches just for this file:
  # use MyApp.CacheCase, caches: [MyApp.ExtraCache]
end
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
