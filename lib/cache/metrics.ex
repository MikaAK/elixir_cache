if Code.ensure_loaded?(:elixir_cache) do
  defmodule Cache.Metrics do
    @moduledoc """
    Add the following metrics for elixir_cache:

    Metrics included:
      - `elixir_cache.cache.call.count` (cache call)
      - `elixir_cache.cache.hit.count` (cache hit)
    """

    import Telemetry.Metrics, only: [counter: 2]

    def metrics do
      [
        counter("elixir_cache.cache.call.count",
          event_name: [:elixir_cache, :cache, :call],
          measurement: :count,
          description: "Total cache calls",
          tags: [:cache_name],
          tag_values: &extract_metadata/1
        ),
        counter("elixir_cache.cache.hit.count",
          event_name: [:elixir_cache, :cache, :hit],
          measurement: :count,
          description: "Cache hit count",
          tags: [:cache_name],
          tag_values: &extract_metadata/1
        )
      ]
    end

    defp extract_metadata(metadata), do: Map.take(metadata, [:cache_name])
  end
end
