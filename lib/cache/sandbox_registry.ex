defmodule Cache.SandboxRegistry do
  @moduledoc """
  Registry for managing isolated cache namespaces in test environments.

  This module provides process-based isolation for cache operations during testing,
  ensuring that concurrent tests don't interfere with each other's cached data.

  ## Features

  * Process-based cache isolation for concurrent tests
  * Automatic namespace generation per test process
  * Simple setup for ExUnit integration

  ## Setup

  Add to your `test_helper.exs`:

      Cache.SandboxRegistry.start_link()

  ## Usage in Tests

      defmodule MyApp.SomeTest do
        use ExUnit.Case, async: true

        setup do
          Cache.SandboxRegistry.start(MyApp.Cache)
          :ok
        end

        test "caching works in isolation" do
          MyApp.Cache.put("key", "value")
          assert {:ok, "value"} = MyApp.Cache.get("key")
        end
      end

  ## Example

      iex> case Cache.SandboxRegistry.start_link() do
      ...>   {:ok, pid} -> is_pid(pid)
      ...>   {:error, {:already_started, pid}} -> is_pid(pid)
      ...> end
      true
  """

  @sleep_for_sync 50
  @registry :elixir_cache_sandbox
  @keys :duplicate

  @spec start_link :: {:error, any} | {:ok, pid}
  def start_link do
    Registry.start_link(keys: @keys, name: @registry)
  end

  def start(cache_or_caches) do
    Cache.SandboxRegistry.register_caches(cache_or_caches)

    if is_list(cache_or_caches) do
      ExUnit.Callbacks.start_supervised!({Cache, cache_or_caches})
    else
      ExUnit.Callbacks.start_supervised!({Cache, [cache_or_caches]})
    end
  end

  def register_caches(cache_module_or_modules, pid \\ self())

  def register_caches(cache_modules, pid) when is_list(cache_modules) do
    Enum.map(cache_modules, &register_caches(&1, pid))
  end

  def register_caches(cache_module, pid) do
    key = unique_id(cache_module, pid)

    res =
      case SandboxRegistry.register(@registry, cache_module.cache_name(), key, @keys) do
        :ok -> :ok
        {:error, :registry_not_started} -> raise_not_started!()
      end

    Process.sleep(@sleep_for_sync)

    res
  end

  def find!(cache_module, pid \\ self()) do
    case SandboxRegistry.lookup(@registry, cache_module.cache_name()) do
      {:ok, unique_id} ->
        unique_id

      {:error, :pid_not_registered} ->
        raise """
        No Cache registered for #{inspect(pid)}

        ======= Use: =======
        #{format_example(cache_module)}
        === in your test ===
        """

      {:error, :registry_not_started} ->
        raise_not_started!()
    end
  end

  defp unique_id(cache_name, pid), do: "#{cache_name}_#{inspect(pid)}"

  defp format_example(cache_module) do
    """
    setup do
      Cache.SandboxRegistry.register_caches(#{inspect(cache_module)})
    end
    """
  end

  defp raise_not_started! do
    raise """
    Registry not started for Cache.Sandbox.
    Please add the line:

    Cache.SandboxRegistry.start_link()

    to test_helper.exs for the current app.
    """
  end
end
