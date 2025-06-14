defmodule ExLLM.MixProject do
  use Mix.Project

  @version "0.6.0"
  @description "Unified Elixir client library for Large Language Models (LLMs)"

  def project do
    [
      app: :ex_llm,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      deps: deps(),
      docs: docs(),
      source_url: "https://github.com/azmaveth/ex_llm",
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        "test.fast": :test,
        "test.unit": :test,
        "test.integration": :test,
        "test.ci": :test,
        "test.all": :test
      ],
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExLLM.Application, []}
    ]
  end

  defp package do
    [
      name: "ex_llm",
      files: ~w(lib docs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/azmaveth/ex_llm",
        "Docs" => "https://hexdocs.pm/ex_llm"
      },
      maintainers: ["azmaveth"]
    ]
  end

  defp deps do
    [
      # HTTP client for API calls
      {:req, "~> 0.5.0"},

      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # WebSocket client for Live API
      {:gun, "~> 2.1"},

      # Configuration file parsing
      {:yaml_elixir, "~> 2.9"},

      # Structured outputs
      {:instructor, "~> 0.1.0"},

      # Dependencies for local model support via Bumblebee
      {:bumblebee, "~> 0.5"},
      {:nx, "~> 0.7"},
      # EXLA has compilation issues on newer macOS - uncomment if needed
      # {:exla, "~> 0.7", optional: true},
      # EMLX for Apple Silicon Metal acceleration
      # Excluded from Hex package until emlx is published
      # Users should add to their mix.exs: {:emlx, github: "elixir-nx/emlx", branch: "main"}
      # {:emlx, github: "elixir-nx/emlx", branch: "main", optional: true},

      # Development and documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:git_hooks, "~> 0.7", only: [:dev], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp docs do
    [
      main: "ExLLM",
      source_ref: "v#{@version}",
      source_url: "https://github.com/azmaveth/ex_llm",
      extras: ["README.md"]
    ]
  end

  defp aliases do
    [
      # Fast local development tests (excludes integration, external, slow tests)
      "test.fast": ["test --exclude integration --exclude external --exclude slow"],

      # Unit tests only
      "test.unit": ["test --only unit"],

      # Integration tests (requires API keys)
      "test.integration": ["test --only integration"],

      # Provider-specific tests
      "test.anthropic": ["test --only provider:anthropic"],
      "test.openai": ["test --only provider:openai"],
      "test.gemini": ["test --only provider:gemini"],
      "test.ollama": ["test --only provider:ollama"],
      "test.openrouter": ["test --only provider:openrouter"],

      # CI configurations
      "test.ci": ["test --exclude wip --exclude flaky --exclude quota_sensitive"],
      "test.ci.full": ["test --exclude wip --exclude flaky"],

      # All tests including slow ones
      "test.all": [
        "test --include slow --include very_slow --include integration --include external"
      ],

      # Experimental/beta features
      "test.experimental": ["test --only experimental --only beta"],

      # OAuth2 tests
      "test.oauth": ["test --only requires_oauth"],

      # Service-dependent tests
      "test.services": ["test --only requires_service"]
    ]
  end
end
