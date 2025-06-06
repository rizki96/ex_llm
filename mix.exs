defmodule ExLLM.MixProject do
  use Mix.Project

  @version "0.3.0"
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
      source_url: "https://github.com/azmaveth/ex_llm"
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
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
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
      
      # Configuration file parsing
      {:yaml_elixir, "~> 2.9"},

      # Structured outputs
      {:instructor, "~> 0.1.0"},

      # Optional dependencies for local model support
      # Comment these out if you have compilation issues
      # {:bumblebee, "~> 0.5", optional: true},
      # {:nx, "~> 0.7", optional: true},
      # {:exla, "~> 0.7", optional: true},

      # Development and documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
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
end
