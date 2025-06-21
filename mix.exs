defmodule ExLLM.MixProject do
  use Mix.Project

  @version "0.8.1"
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
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :logger, :telemetry, :req, :tesla, :ecto, :yaml_elixir],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
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

      # HTTP client with middleware support
      {:tesla, "~> 1.8"},

      # WebSocket client for Live API
      {:gun, "~> 2.1"},

      # HTTP client for streaming (Tesla adapter)
      {:hackney, "~> 1.20"},

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
      {:excoveralls, "~> 0.18", only: :test},

      # Environment variable loading
      {:dotenv, "~> 3.1", only: [:dev, :test]}
    ]
  end

  defp docs do
    [
      main: "ExLLM",
      source_ref: "v#{@version}",
      source_url: "https://github.com/azmaveth/ex_llm",
      extras: [
        "README.md",
        "docs/API_REFERENCE.md",
        "docs/QUICKSTART.md",
        "docs/USER_GUIDE.md",
        "docs/TESTING.md",
        "docs/LOGGER.md",
        "docs/PROVIDER_CAPABILITIES.md",
        "guides/internal_modules.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: [
          "docs/QUICKSTART.md",
          "docs/USER_GUIDE.md",
          "docs/TESTING.md",
          "guides/internal_modules.md"
        ],
        References: [
          "docs/API_REFERENCE.md",
          "docs/LOGGER.md",
          "docs/PROVIDER_CAPABILITIES.md"
        ]
      ]
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

      # External tests
      "test.external": ["test --only external"],

      # Live API tests
      "test.live_api": ["test --only live_api"],

      # Local-only tests (no API calls)
      "test.local_only": ["test --exclude live_api --exclude external --exclude integration"],

      # Provider-specific tests
      "test.anthropic": ["test --only provider:anthropic"],
      "test.openai": ["test --only provider:openai"],
      "test.gemini": ["test --only provider:gemini"],
      "test.groq": ["test --only provider:groq"],
      "test.mistral": ["test --only provider:mistral"],
      "test.openrouter": ["test --only provider:openrouter"],
      "test.perplexity": ["test --only provider:perplexity"],
      "test.ollama": ["test --only provider:ollama"],
      "test.lmstudio": ["test --only provider:lmstudio"],
      "test.bumblebee": ["test --only provider:bumblebee"],

      # Capability-based tests
      "test.streaming": ["test --only streaming"],
      "test.vision": ["test --only vision"],
      "test.multimodal": ["test --only multimodal"],
      "test.function_calling": ["test --only function_calling"],
      "test.embedding": ["test --only embedding"],

      # Test type tests
      "test.oauth2": ["test --only requires_oauth"],

      # CI configurations
      "test.ci": ["test --exclude wip --exclude flaky --exclude quota_sensitive"],
      "test.ci.full": ["test --exclude wip --exclude flaky"],

      # All tests including slow ones
      "test.all": [
        "test --include slow --include very_slow --include integration --include external"
      ],

      # Experimental/beta features
      "test.experimental": ["test --only experimental --only beta"],

      # Service-dependent tests
      "test.services": ["test --only requires_service"]
    ]
  end
end
