defmodule ExLLM.MixProject do
  use Mix.Project

  @version "1.0.0-rc1"
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
        plt_apps: [
          :erts,
          :kernel,
          :stdlib,
          :crypto,
          :elixir,
          :logger,
          :telemetry,
          :jason,
          :req,
          :tesla,
          :hackney,
          :gun,
          :yaml_elixir,
          :ex_llm
        ],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def application do
    [
      extra_applications:
        [
          :logger,
          :telemetry,
          :jason,
          :req,
          :tesla,
          :hackney,
          :gun,
          :yaml_elixir
        ] ++ optional_applications(),
      mod: {ExLLM.Application, []}
    ]
  end

  # Include optional dependencies only if they are available
  defp optional_applications do
    []
    |> maybe_add_application(:bumblebee)
    |> maybe_add_application(:nx)
  end

  defp maybe_add_application(apps, app) do
    # Check if the dependency is actually available and loaded
    case Code.ensure_loaded?(app) do
      true -> [app | apps]
      false -> apps
    end
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

      # Dependencies for local model support via Bumblebee (optional)
      {:bumblebee, "~> 0.6.2", optional: true},
      {:nx, "~> 0.7", optional: true},
      # EXLA has compilation issues on newer macOS - uncomment if needed
      # {:exla, "~> 0.7", optional: true},
      # EMLX for Apple Silicon Metal acceleration
      # Excluded from Hex package until emlx is published
      # Users should add to their mix.exs: {:emlx, github: "elixir-nx/emlx", branch: "main"}
      # {:emlx, github: "elixir-nx/emlx", branch: "main", optional: true},

      # Development and documentation
      {:ex_doc, "~> 0.38.2", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:git_hooks, "~> 0.7", only: [:dev], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},

      # HTTP testing mock server
      {:bypass, "~> 2.1", only: :test},

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
      # === CORE TESTING STRATEGY ===

      # Live API tests (refreshes cache, comprehensive)
      "test.live": [
        "cmd MIX_RUN_LIVE=true mix test --include live_api --include external --include integration"
      ],

      # Fast development tests (excludes API calls and slow tests)
      "test.fast": [
        "test --exclude live_api --exclude external --exclude integration --exclude slow"
      ],

      # Unit tests only (pure logic, no external dependencies)
      "test.unit": ["test --only unit"],

      # Integration tests (requires API keys)
      "test.integration": ["test --include integration --include external"],

      # All tests including slow/comprehensive suites
      "test.all": [
        "test --include slow --include very_slow --include integration --include external"
      ],

      # === PROVIDER-SPECIFIC TESTING ===

      # Major cloud providers (covers 80% of usage)
      "test.anthropic": ["test --only provider:anthropic"],
      "test.openai": ["test --only provider:openai"],
      "test.gemini": ["test --only provider:gemini"],

      # Local providers (for offline development)
      "test.local": [
        "test --only provider:ollama --only provider:lmstudio"
      ],

      # Bumblebee tests (requires explicit opt-in due to large model downloads)
      "test.bumblebee": [
        "cmd EX_LLM_START_MODELLOADER=true mix test --only provider:bumblebee --include requires_deps"
      ],

      # === SPECIALIZED TESTING ===

      # OAuth2 authentication tests
      "test.oauth2": ["test --only requires_oauth"],

      # CI/CD pipeline tests
      "test.ci": [
        "test --exclude wip --exclude flaky --exclude quota_sensitive --exclude very_slow"
      ],

      # === CACHE MANAGEMENT ===

      "cache.clear": ["cmd rm -rf test/cache/*"],
      "cache.status": ["run -e ExLLM.Testing.Cache.status()"]
    ]
  end
end
