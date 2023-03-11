defmodule Cache.Redis.Global do
  @moduledoc """
  Contains General functions for interfacing with redis
  """

  @default_scan_count 10

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

  def scan(pool_name, scan_opts, _opts) do
    match = scan_opts[:match] || "*"
    count = scan_opts[:count] || @default_scan_count
    type = scan_opts[:type]

    with {:ok, elements} <- scan_and_paginate(pool_name, "SCAN", nil, 0, match, count, type) do
      keys = Enum.map(elements, &String.replace_leading(&1, "#{pool_name}:", ""))
      {:ok, keys}
    end
  end
  defp scan_and_paginate(acc \\ [], pool_name, operation, key, cursor, match, count, type) do
    with {:ok, data} <-
           command(
             pool_name,
             redis_scan_command(pool_name, operation, key, cursor, match, count, type)
           ) do
      case data do
        ["0", elements] ->
          {:ok, acc ++ elements}

        [cursor, elements] ->
          scan_and_paginate(
            acc ++ elements,
            pool_name,
            operation,
            key,
            cursor,
            match,
            count,
            type
          )
      end
    end
  end

  defp redis_scan_command(pool_name, "SCAN", _key, cursor, match, count, nil) do
    ["SCAN", cursor, "MATCH", "#{pool_name}:#{match}", "COUNT", count]
  end

  defp redis_scan_command(pool_name, "SCAN", _key, cursor, match, count, type) do
    ["SCAN", cursor, "MATCH", "#{pool_name}:#{match}", "COUNT", count, "TYPE", type]
  end
  defp handle_response({:ok, "OK"}), do: :ok
  defp handle_response({:ok, _} = res), do: res
  defp handle_response({:error, %Redix.ConnectionError{reason: reason}}) do
    {:error, ErrorMessage.service_unavailable("redis connection errored because: #{reason}")}
  end

  defp handle_response({:error, _} = res), do: res
end
