defmodule Cache.Redis.Global do
  @moduledoc false

  @default_scan_count 10

  def cache_key(pool_name, key) do
    "#{pool_name}:#{key}"
  end

  def command(pool_name, command, opts \\ []) do
    opts = Keyword.delete(opts, :uri)

    :poolboy.transaction(pool_name, fn pid ->
      pid |> Redix.command(command, opts) |> handle_response
    end)
  end

  def command!(pool_name, command, opts \\ []) do
    opts = Keyword.delete(opts, :uri)

    :poolboy.transaction(pool_name, fn pid ->
      Redix.command!(pid, command, opts)
    end)
  end

  def pipeline(pool_name, commands, opts \\ []) do
    opts = Keyword.delete(opts, :uri)

    :poolboy.transaction(pool_name, fn pid ->
      pid |> Redix.pipeline(commands, opts) |> handle_response
    end)
  end

  def pipeline!(pool_name, commands, opts \\ []) do
    opts = Keyword.delete(opts, :uri)

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

  defguard is_scan_op(operation) when operation in ["HSCAN", "SSCAN", "ZSCAN"]

  def scan_collection(pool_name, operation, key, scan_opts, _opts) when is_scan_op(operation) do
    match = scan_opts[:match] || "*"
    count = scan_opts[:count] || @default_scan_count
    type = scan_opts[:type]

    scan_and_paginate(pool_name, operation, key, 0, match, count, type)
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

  defp redis_scan_command(pool_name, operation, key, cursor, match, count, nil) do
    [operation, "#{pool_name}:#{key}", cursor, "MATCH", match, "COUNT", count]
  end

  defp handle_response({:ok, "OK"}), do: :ok
  defp handle_response({:ok, _} = res), do: res

  defp handle_response({:error, %Redix.ConnectionError{reason: reason}}) do
    {:error, ErrorMessage.service_unavailable("redis connection errored because: #{reason}")}
  end

  defp handle_response({:error, %Redix.Error{message: "ERR Path" <> _rest = message}}) do
    {:error, ErrorMessage.not_found(message)}
  end

  defp handle_response(
         {:error, %Redix.Error{message: "ERR new objects must be created at the root" = message}}
       ) do
    {:error, ErrorMessage.bad_request(message)}
  end

  defp handle_response({:error, error}) do
    {:error, ErrorMessage.internal_server_error("Internal server error", %{error: inspect(error)})}
  end
end
