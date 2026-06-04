defmodule Cache.Gen do
  @moduledoc """
  Tiny unique-data generators for the test suite.

  Replaces the (unmaintained) `:faker` dependency, which the tests only ever
  used to produce unique cache keys and values. Uniqueness is all the tests
  need, so these lean on `System.unique_integer/1`.
  """

  @doc ~S(Unique cache key string, e.g. `"key-12"`.)
  @spec key() :: String.t()
  def key, do: "key-#{System.unique_integer([:positive])}"

  @doc ~S(Unique cache value string, e.g. `"value-13"`.)
  @spec value() :: String.t()
  def value, do: "value-#{System.unique_integer([:positive])}"
end
