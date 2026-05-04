defmodule Cache.Config do
  @moduledoc false

  @app :elixir_cache

  def sandbox_sleep_ms do
    Application.get_env(@app, :sandbox_sleep_ms, 50)
  end
end
