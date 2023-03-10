defmodule Cache.Redis.Global do
  @moduledoc """
  Contains General functions for interfacing with redis
  """

  def cache_key(pool_name, key) do
    "#{pool_name}:#{key}"
  end

  def command(pool_name, command, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      pid |> Redix.command(command, opts) |> handle_response
    end)
  end

  def command!(pool_name, command, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      Redix.command!(pid, command, opts)
    end)
  end

  def pipeline(pool_name, commands, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      pid |> Redix.pipeline(commands, opts) |> handle_response
    end)
  end

  def pipeline!(pool_name, commands, opts \\ []) do
    :poolboy.transaction(pool_name, fn pid ->
      Redix.pipeline!(pid, commands, opts)
    end)
  end

  defp handle_response({:ok, "OK"}), do: :ok
  defp handle_response({:ok, _} = res), do: res
  defp handle_response({:error, %Redix.ConnectionError{reason: reason}}) do
    {:error, ErrorMessage.service_unavailable("redis connection errored because: #{reason}")}
  end

  defp handle_response({:error, _} = res), do: res
end
