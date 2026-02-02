defmodule Cache.DoctestTest do
  use ExUnit.Case, async: true

  doctest Cache.Agent
  doctest Cache.ETS
  doctest Cache.DETS
  doctest Cache.Sandbox
  doctest Cache.SandboxRegistry
  doctest Cache.TermEncoder
end
