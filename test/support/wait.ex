defmodule Cache.Wait do
  @moduledoc """
  Polls a condition so tests synchronize on observable state instead of sleeping.
  """

  @poll_interval_ms 10

  @doc "Returns `true` as soon as `fun` returns a truthy value, or `false` once `timeout` ms elapse."
  @spec until((-> as_boolean(term())), non_neg_integer()) :: boolean()
  def until(fun, timeout \\ 1_000) do
    poll(fun, System.monotonic_time(:millisecond) + timeout)
  end

  defp poll(fun, deadline) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true ->
        Process.sleep(@poll_interval_ms)
        poll(fun, deadline)
    end
  end
end
