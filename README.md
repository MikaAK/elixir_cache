# ElixirCache
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
    opts: [...otps]
end
```
