defmodule ElixirCache.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_cache,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: "Standardized and testable caching across your app. In test caches are isolated.",
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:error_message, "~> 0.3"},
      {:redix, "~> 1.2"},
      {:poolboy, "~> 1.5"},

      {:nimble_options, "~> 0.5"},
      {:sandbox_registry, "~> 0.1"},
      {:jason, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev},

      {:telemetry, "~> 1.1"},
      {:telemetry_metrics, "~> 0.6.1"},

      {:excoveralls, "~> 0.10", only: :test},
      {:credo, "~> 1.6", only: [:test, :dev], runtime: false},
      {:blitz_credo_checks, "~> 0.1", only: [:test, :dev], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Mika Kalathil"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/mikaak/elixir_cache"},
      files: ~w(mix.exs README.md CHANGELOG.md LICENSE lib)
    ]
  end

  defp docs do
    [
      main: "Cache",
      source_url: "https://github.com/mikaak/elixir_cache",

      groups_for_modules: [
        "Adapters": [
          Cache.Agent,
          Cache.ETS,
          Cache.Redis
          # Cache.ConCache
        ]
      ]
    ]
  end
end
