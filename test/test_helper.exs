# App-env fixtures for the `opts: :app` / `opts: {:app, :key}` cases in test/cache_test.exs
Application.put_env(:elixir_cache, CacheTest.TestCache.RedisRuntimeAppEnv, host: "localhost", port: 6379)
Application.put_env(:elixir_cache, :cache, host: "localhost", port: 6379)

Cache.SandboxRegistry.start_link()

ExUnit.start()
