if Code.ensure_loaded?(:prometheus_telemetry) do
  defmodule Cache.Metrics do
    @moduledoc """
    Add the following metrics for elixir_cache:

    Metrics included:
      - `elixir_cache.cache.get.count`
      - `elixir_cache.cache.get.miss.count`
      - `elixir_cache.cache.get.error.count`
      - `elixir_cache.cache.put.count`
      - `elixir_cache.cache.delete.count`
      - `elixir_cache.cache.get.duration.millisecond`
    """

    import Telemetry.Metrics, only: [counter: 2, distribution: 2]

    @duration_unit {:native, :millisecond}
    @buckets PrometheusTelemetry.Config.default_millisecond_buckets()

    def metrics do
      [
        counter("elixir_cache.cache.get.count",
          event_name: [:elixir_cache, :cache, :get],
          measurement: :count,
          description: "Total cache calls",
          tags: [:cache_name, :action],
          tag_values: &extract_cache_metadata/1
        ),
        counter("elixir_cache.cache.get.miss.count",
          event_name: [:elixir_cache, :cache, :get, :miss],
          measurement: :count,
          description: "Cache miss count",
          tags: [:cache_name, :action, :result],
          tag_values: &extract_cache_metadata/1
        ),
        counter("elixir_cache.cache.get.error.count",
          event_name: [:elixir_cache, :cache, :get, :error],
          measurement: :count,
          description: "Cache error count",
          tags: [:cache_name, :action, :result],
          tag_values: &extract_cache_metadata/1
        ),
        counter("elixir_cache.cache.put.count",
          event_name: [:elixir_cache, :cache, :put],
          measurement: :count,
          description: "Cache put count",
          tags: [:cache_name, :action],
          tag_values: &extract_cache_metadata/1
        ),
        counter("elixir_cache.cache.delete.count",
          event_name: [:elixir_cache, :cache, :delete],
          measurement: :count,
          description: "Cache delete count",
          tags: [:cache_name, :action],
          tag_values: &extract_cache_metadata/1
        ),
        distribution("elixir_cache.cache.get.duration.millisecond",
          event_name: [:elixir_cache, :cache, :get, :stop],
          measurement: :duration,
          description: "Time taken for cache get",
          tags: [:cache_name, :duration],
          tag_values: &extract_cache_metadata/1,
          unit: @duration_unit,
          reporter_options: [buckets: @buckets]
        ),
        distribution("elixir_cache.cache.put.duration.millisecond",
          event_name: [:elixir_cache, :cache, :put, :stop],
          measurement: :duration,
          description: "Time taken for cache put",
          tags: [:cache_name, :duration],
          tag_values: &extract_cache_metadata/1,
          unit: @duration_unit,
          reporter_options: [buckets: @buckets]
        ),
        distribution("elixir_cache.cache.delete.duration.millisecond",
          event_name: [:elixir_cache, :cache, :delete, :stop],
          measurement: :duration,
          description: "Time taken for cache delete",
          tags: [:cache_name, :duration],
          tag_values: &extract_cache_metadata/1,
          unit: @duration_unit,
          reporter_options: [buckets: @buckets]
        )
      ]
    end

    defp extract_cache_metadata(metadata) do
      Map.take(metadata, [:cache_name, :action, :duration])
    end
  end
end
