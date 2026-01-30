defmodule Cache.OTPVersion do
  @moduledoc false

  @otp_release String.to_integer(to_string(:erlang.system_info(:otp_release)))

  def otp_release, do: @otp_release

  defmacro otp_release_at_least?(version) do
    otp_release = @otp_release

    quote do
      unquote(otp_release) >= unquote(version)
    end
  end
end
