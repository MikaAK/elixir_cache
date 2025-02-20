defmodule Cache.MetricsTest do
  use ExUnit.Case, async: true

  alias Cache.Metrics
  import Telemetry.Metrics

  test "returns the expected telemetry metrics" do
    metrics = Metrics.metrics()

    expected_metrics = [
      %Telemetry.Metrics.Counter{
        name: "elixir_cache.cache.call.count",
        event_name: [:elixir_cache, :cache, :call],
        measurement: :count,
        description: "Total cache calls",
        tags: [:cache_name],
        tag_values: &Metrics.extract_metadata/1
      },
      %Telemetry.Metrics.Counter{
        name: "elixir_cache.cache.hit.count",
        event_name: [:elixir_cache, :cache, :hit],
        measurement: :count,
        description: "Cache hit count",
        tags: [:cache_name],
        tag_values: &Metrics.extract_metadata/1
      }
    ]

    for expected_metric <- expected_metrics do
      assert Enum.any?(metrics, fn metric ->
        Map.take(metric, [:name, :event_name, :measurement, :description, :tags, :tag_values]) ==
        Map.take(expected_metric, [:name, :event_name, :measurement, :description, :tags, :tag_values])
      end), "Expected metric #{expected_metric.name} was not found."
    end
  end
end
