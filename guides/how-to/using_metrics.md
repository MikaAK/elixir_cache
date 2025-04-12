# How to Use Metrics and Telemetry with ElixirCache

ElixirCache integrates with Elixir's telemetry system to provide observability for your cache operations. This guide explains how to set up and use these metrics in your application.

## Understanding ElixirCache Telemetry Events

ElixirCache emits the following telemetry events:

| Event Name | Description |
|------------|-------------|
| `[:elixir_cache, :cache, :put]` | Emitted when a value is stored in the cache |
| `[:elixir_cache, :cache, :get]` | Emitted when a value is retrieved from the cache |
| `[:elixir_cache, :cache, :get, :miss]` | Emitted when a cache lookup results in a miss |
| `[:elixir_cache, :cache, :delete]` | Emitted when a value is deleted from the cache |
| `[:elixir_cache, :cache, :put, :error]` | Emitted when an error occurs during a put operation |
| `[:elixir_cache, :cache, :get, :error]` | Emitted when an error occurs during a get operation |
| `[:elixir_cache, :cache, :delete, :error]` | Emitted when an error occurs during a delete operation |

## Setting Up Basic Telemetry Handlers

To start collecting metrics, you need to attach handlers to these telemetry events:

```elixir
defmodule MyApp.CacheMetrics do
  def setup do
    # Attach handlers for cache operations
    :telemetry.attach(
      "cache-get-handler",
      [:elixir_cache, :cache, :get],
      &handle_cache_get/4,
      nil
    )

    :telemetry.attach(
      "cache-miss-handler",
      [:elixir_cache, :cache, :get, :miss],
      &handle_cache_miss/4,
      nil
    )

    :telemetry.attach(
      "cache-put-handler",
      [:elixir_cache, :cache, :put],
      &handle_cache_put/4,
      nil
    )

    :telemetry.attach(
      "cache-delete-handler",
      [:elixir_cache, :cache, :delete],
      &handle_cache_delete/4,
      nil
    )

    # Attach handlers for error events
    :telemetry.attach(
      "cache-get-error-handler",
      [:elixir_cache, :cache, :get, :error],
      &handle_cache_error/4,
      nil
    )

    :telemetry.attach(
      "cache-put-error-handler",
      [:elixir_cache, :cache, :put, :error],
      &handle_cache_error/4,
      nil
    )

    :telemetry.attach(
      "cache-delete-error-handler",
      [:elixir_cache, :cache, :delete, :error],
      &handle_cache_error/4,
      nil
    )
  end

  def handle_cache_get(_event, _measurements, metadata, _config) do
    IO.puts("Cache GET operation for cache: #{metadata.cache_name}")
  end

  def handle_cache_miss(_event, measurements, metadata, _config) do
    IO.puts("Cache MISS for cache: #{metadata.cache_name}, count: #{measurements.count}")
  end

  def handle_cache_put(_event, _measurements, metadata, _config) do
    IO.puts("Cache PUT operation for cache: #{metadata.cache_name}")
  end

  def handle_cache_delete(_event, _measurements, metadata, _config) do
    IO.puts("Cache DELETE operation for cache: #{metadata.cache_name}")
  end

  def handle_cache_error(event, measurements, metadata, _config) do
    [_, _, operation, _] = event
    IO.puts("Cache #{operation} ERROR for cache: #{metadata.cache_name}: #{inspect(metadata.error)}")
  end
end
```

Start these handlers in your application supervision tree:

```elixir
def start(_type, _args) do
  # Set up telemetry handlers
  MyApp.CacheMetrics.setup()

  children = [
    # ... other children
    MyApp.Cache
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Integration with Telemetry Metrics

ElixirCache works well with `telemetry_metrics` for defining and collecting metrics:

```elixir
defmodule MyApp.Metrics do
  import Telemetry.Metrics

  def metrics do
    [
      # Counter metrics
      counter("elixir_cache.cache.get.count", tags: [:cache_name]),
      counter("elixir_cache.cache.get.miss.count", tags: [:cache_name]),
      counter("elixir_cache.cache.put.count", tags: [:cache_name]),
      counter("elixir_cache.cache.delete.count", tags: [:cache_name]),
      
      # Error metrics
      counter("elixir_cache.cache.get.error.count", tags: [:cache_name, :error]),
      counter("elixir_cache.cache.put.error.count", tags: [:cache_name, :error]),
      counter("elixir_cache.cache.delete.error.count", tags: [:cache_name, :error]),
      
      # Duration metrics (for span events)
      distribution("elixir_cache.cache.get.duration", unit: {:native, :millisecond}, tags: [:cache_name]),
      distribution("elixir_cache.cache.put.duration", unit: {:native, :millisecond}, tags: [:cache_name]),
      distribution("elixir_cache.cache.delete.duration", unit: {:native, :millisecond}, tags: [:cache_name])
    ]
  end
end
```

## Integrating with Common Reporting Tools

### Prometheus

Using `prometheus_telemetry`:

```elixir
defmodule MyApp.PrometheusMetrics do
  def setup do
    # Define metrics that Prometheus will collect
    metrics = MyApp.Metrics.metrics()
    
    # Attach Prometheus reporters to these metrics
    :prometheus_telemetry.setup(metrics)
    
    # Start the Prometheus metrics HTTP endpoint
    Plug.Cowboy.http(PrometheusTelemetry.Plug, [], port: 9568)
  end
end
```

### StatsD

Using `telemetry_metrics_statsd`:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      {TelemetryMetricsStatsd, metrics: MyApp.Metrics.metrics()},
      
      # ... other children
      MyApp.Cache
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Creating Custom Cache Metrics

You can also create custom metrics specific to your application's needs:

```elixir
defmodule MyApp.CustomCacheMetrics do
  # Track the size of values being stored
  def track_value_size(key, value) do
    byte_size = :erlang.term_to_binary(value) |> byte_size()
    
    :telemetry.execute(
      [:my_app, :cache, :value_size],
      %{bytes: byte_size},
      %{key: key}
    )
  end
  
  # Track cache hit ratio
  def track_hit_ratio() do
    # Attach to both get and miss events
    :telemetry.attach(
      "hit-ratio-get-handler",
      [:elixir_cache, :cache, :get],
      &handle_get/4,
      %{hits: 0, misses: 0}
    )
    
    :telemetry.attach(
      "hit-ratio-miss-handler",
      [:elixir_cache, :cache, :get, :miss],
      &handle_miss/4,
      %{hits: 0, misses: 0}
    )
  end
  
  defp handle_get(_event, _measurements, _metadata, config) do
    hits = config.hits + 1
    ratio = hits / (hits + config.misses)
    
    :telemetry.execute(
      [:my_app, :cache, :hit_ratio],
      %{ratio: ratio},
      %{}
    )
    
    %{hits: hits, misses: config.misses}
  end
  
  defp handle_miss(_event, _measurements, _metadata, config) do
    misses = config.misses + 1
    ratio = config.hits / (config.hits + misses)
    
    :telemetry.execute(
      [:my_app, :cache, :hit_ratio],
      %{ratio: ratio},
      %{}
    )
    
    %{hits: config.hits, misses: misses}
  end
end
```

## Best Practices for Cache Metrics

1. **Monitor hit/miss ratio**: A low hit ratio may indicate cache keys that expire too quickly or ineffective caching strategies.

2. **Track cache size**: For in-memory caches like ETS, monitor the memory usage to prevent excessive memory consumption.

3. **Watch for error rates**: Sudden increases in error events might indicate connectivity issues (for Redis) or other problems.

4. **Measure operation durations**: Unusually long cache operations could signal network latency or overloaded cache servers.

5. **Set alerts**: Configure alerts for abnormal metrics like high miss rates, increasing error rates, or excessive latency.

6. **Segment by cache name**: Always include the cache name in your metrics to distinguish between different caches in your application.

7. **Correlate with application metrics**: Analyze how cache performance affects overall application performance.
