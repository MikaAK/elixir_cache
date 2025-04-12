defmodule ElixirCache.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_cache,
      version: "0.3.8",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      description: "Standardized and testable caching across your app. In test caches are isolated.",
      deps: deps(),
      docs: docs(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix, :credo],
        list_unused_filters: true,
        plt_local_path: "dialyzer",
        plt_core_path: "dialyzer"
      ],
      preferred_cli_env: [
        dialyzer: :test,
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

      {:con_cache, "~> 1.0"},
      {:nimble_options, "~> 1.0"},
      {:sandbox_registry, "~> 0.1"},
      {:jason, "~> 1.0"},

      {:telemetry, "~> 1.1"},
      {:telemetry_metrics, "~> 1.0"},
      {:prometheus_telemetry, "~> 0.3", optional:  true},

      {:faker, "~> 0.17", only: [:test]},
      {:credo, "~> 1.6", only: [:test, :dev], runtime: false},
      {:blitz_credo_checks, "~> 0.1", only: [:test, :dev], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, ">= 0.0.0", optional: true, only: :dev},
      {:dialyxir, "~> 1.0", optional: true, only: :test, runtime: false}
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
      main: "introduction",
      source_url: "https://github.com/mikaak/elixir_cache",
      extras: [
        "guides/introduction.md",
        "guides/tutorials/installation.md",
        "guides/tutorials/basic_operations.md",
        "guides/tutorials/advanced_techniques.md",
        "guides/how-to/choosing_adapter.md",
        "guides/how-to/redis_setup.md",
        "guides/how-to/testing_with_cache.md",
        "guides/how-to/using_metrics.md",
        "guides/explanation/architecture.md",
        "guides/reference/api.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        "Getting Started": ["guides/introduction.md"],
        "Tutorials": [~r{guides/tutorials/.?}],
        "How-to Guides": [~r{guides/how-to/.?}],
        "Explanation": [~r{guides/explanation/.?}],
        "Reference": [~r{guides/reference/.?}],
        "Changelog": ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Main": [Cache],

        "Adapters": [
          Cache.Agent,
          Cache.ETS,
          Cache.DETS,
          Cache.Redis,
          Cache.ConCache
        ],

        "Test Utils": [
          Cache.Sandbox,
          Cache.SandboxRegistry
        ],

        "Internal": [
          Cache.TermEncoder,
          Cache.Metrics
        ]
      ]
    ]
  end
end
