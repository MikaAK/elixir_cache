# Advanced Cache Techniques

This tutorial covers more advanced patterns and techniques for using ElixirCache in your applications.

## Working with Cache TTL (Time To Live)

Setting appropriate TTL values is important for efficient cache usage:

```elixir
# Cache for 10 seconds
MyApp.Cache.put("short-lived-key", :timer.seconds(10), %{data: "expires quickly"})

# Cache for 1 hour
MyApp.Cache.put("hourly-key", :timer.hours(1), %{data: "expires in an hour"})

# Cache for 1 day
MyApp.Cache.put("daily-key", :timer.hours(24), %{data: "expires in a day"})

# Cache indefinitely (no TTL)
MyApp.Cache.put("permanent-key", %{data: "never expires"})
```

## Using Function Memoization

You can implement function memoization using ElixirCache:

```elixir
defmodule MyApp.MemoizedCalculator do
  def factorial(n, cache \\ MyApp.Cache) do
    cache_key = "factorial:#{n}"
    
    case cache.get(cache_key) do
      {:ok, result} when not is_nil(result) ->
        result
        
      _ ->
        # Calculate the result if not in cache
        result = calculate_factorial(n)
        
        # Store in cache for future use (cache for 1 hour)
        cache.put(cache_key, 3600, result)
        
        result
    end
  end
  
  defp calculate_factorial(0), do: 1
  defp calculate_factorial(1), do: 1
  defp calculate_factorial(n) when n > 1, do: n * factorial(n - 1)
end
```

## Implementing Cache Stampede Protection

Cache stampede occurs when many requests try to regenerate a cached item simultaneously:

```elixir
defmodule MyApp.StampedeProtection do
  # Stale-while-revalidate pattern
  def get_with_protection(key, ttl, stale_ttl, generator_fn) do
    case MyApp.Cache.get(key) do
      # Cache hit - return value
      {:ok, %{value: value, timestamp: ts}} ->
        now = System.system_time(:second)
        
        # If stale but not expired, return stale value and trigger background refresh
        if now - ts > stale_ttl and now - ts < ttl do
          Task.start(fn -> 
            refresh_cache(key, ttl, generator_fn) 
          end)
        end
        
        {:ok, value}
        
      # Cache miss - generate and store
      _ ->
        refresh_cache(key, ttl, generator_fn)
    end
  end
  
  defp refresh_cache(key, ttl, generator_fn) do
    with {:ok, value} <- generator_fn.() do
      cached_value = %{
        value: value,
        timestamp: System.system_time(:millisecond)
      }
      
      MyApp.Cache.put(key, ttl, cached_value)
      {:ok, value}
    end
  end
end
```

## Using Cache Prefixing for Namespaces

Organize your cache keys using prefixes:

```elixir
defmodule MyApp.UserCache do
  @prefix "user:"
  
  def store_user(user_id, user_data) do
    MyApp.Cache.put("#{@prefix}#{user_id}", user_data)
  end
  
  def get_user(user_id) do
    MyApp.Cache.get("#{@prefix}#{user_id}")
  end
  
  def invalidate_user(user_id) do
    MyApp.Cache.delete("#{@prefix}#{user_id}")
  end
  
  # Bulk invalidation in ETS cache
  def invalidate_all_users() do
    if MyApp.Cache.cache_adapter() == Cache.ETS do
      MyApp.Cache.match_delete({:"#{@prefix}_", :_})
    else
      # Fallback for other adapters without pattern matching
      {:error, :not_supported}
    end
  end
end
```

## Caching Database Queries

A common pattern is caching database query results:

```elixir
defmodule MyApp.PostRepository do
  def get_featured_posts do
    cache_key = "featured_posts"
    
    case MyApp.Cache.get(cache_key) do
      {:ok, posts} when is_list(posts) ->
        {:ok, posts}
        
      _ ->
        # Query from database if not in cache
        with {:ok, posts} <- fetch_featured_posts_from_db() do
          # Cache for 15 minutes
          :ok = MyApp.Cache.put(cache_key, :timer.minutes(15), posts)
          {:ok, posts}
        end
    end
  end
  
  defp fetch_featured_posts_from_db do
    # Database query logic here
    # ...
  end
end
```

## Working with Telemetry for Cache Monitoring

Implement telemetry handlers to monitor cache performance:

```elixir
defmodule MyApp.CacheMonitor do
  def setup do
    :telemetry.attach(
      "cache-hit-rate-tracker",
      [:elixir_cache, :cache, :get],
      &handle_get_event/4,
      %{hits: 0, total: 0}
    )
    
    :telemetry.attach(
      "cache-miss-tracker",
      [:elixir_cache, :cache, :get, :miss],
      &handle_miss_event/4,
      %{misses: 0}
    )
  end
  
  def handle_get_event(_event, _measurements, _metadata, state) do
    total = state.total + 1
    
    if rem(total, 100) == 0 do
      hit_rate = state.hits / total
      IO.puts("Cache hit rate: #{hit_rate * 100}%")
    end
    
    %{state | total: total}
  end
  
  def handle_miss_event(_event, _measurements, _metadata, state) do
    misses = state.misses + 1
    %{state | misses: misses}
  end
end
```

