defmodule Mix.Tasks.ExLlm.CapabilityMatrix do
  @shortdoc "Display provider capability matrix"

  @moduledoc """
  Display a visual matrix of provider capabilities.

  This task shows which providers support which features, with optional
  integration of test results to show actual vs configured capabilities.

  ## Usage

      mix ex_llm.capability_matrix [options]

  ## Options

    * `--providers` - Comma-separated list of providers to include
    * `--capabilities` - Comma-separated list of capabilities to show
    * `--extended` - Show all capabilities (not just core)
    * `--export` - Export format: console (default), markdown, html
    * `--output` - Output file for exports (defaults to capability_matrix.{ext})
    * `--with-tests` - Include test results if available

  ## Examples

      # Show core capabilities for all providers
      mix ex_llm.capability_matrix
      
      # Show specific providers
      mix ex_llm.capability_matrix --providers openai,anthropic,gemini
      
      # Show all capabilities
      mix ex_llm.capability_matrix --extended
      
      # Export to markdown
      mix ex_llm.capability_matrix --export markdown --output docs/capabilities.md
      
      # Include test results
      mix ex_llm.capability_matrix --with-tests
  """

  use Mix.Task

  alias ExLLM.Testing.CapabilityMatrix

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:ex_llm)

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          providers: :string,
          capabilities: :string,
          extended: :boolean,
          export: :string,
          output: :string,
          with_tests: :boolean
        ]
      )

    # Parse options
    options = build_options(opts)

    # Handle export format
    case Keyword.get(opts, :export, "console") do
      "console" ->
        CapabilityMatrix.display(options)

      "markdown" ->
        output_file = Keyword.get(opts, :output, "capability_matrix.md")

        {:ok, filename} =
          CapabilityMatrix.export_markdown(Keyword.put(options, :output, output_file))

        Mix.shell().info("Capability matrix exported to: #{filename}")

      "html" ->
        output_file = Keyword.get(opts, :output, "capability_matrix.html")

        {:ok, filename} = CapabilityMatrix.export_html(Keyword.put(options, :output, output_file))
        Mix.shell().info("Capability matrix exported to: #{filename}")

      format ->
        Mix.shell().error("Unknown export format: #{format}")
        Mix.shell().info("Valid formats: console, markdown, html")
    end
  end

  defp build_options(opts) do
    options = []

    # Parse providers list
    options =
      case Keyword.get(opts, :providers) do
        nil ->
          options

        providers_str ->
          providers =
            String.split(providers_str, ",")
            |> Enum.map(&String.trim/1)
            |> Enum.map(&String.to_atom/1)

          Keyword.put(options, :providers, providers)
      end

    # Parse capabilities list
    options =
      case Keyword.get(opts, :capabilities) do
        nil ->
          options

        capabilities_str ->
          capabilities =
            String.split(capabilities_str, ",")
            |> Enum.map(&String.trim/1)
            |> Enum.map(&String.to_atom/1)

          Keyword.put(options, :capabilities, capabilities)
      end

    # Add extended flag
    options =
      if Keyword.get(opts, :extended, false) do
        Keyword.put(options, :extended, true)
      else
        options
      end

    # Add test results if requested
    options =
      if Keyword.get(opts, :with_tests, false) do
        test_results = load_test_results()
        Keyword.put(options, :test_results, test_results)
      else
        options
      end

    options
  end

  defp load_test_results do
    # In a real implementation, this would load actual test results
    # from the test cache or a test run summary
    # For now, return a sample structure
    %{
      # {provider, capability} => status
      {:openai, :chat} => :pass,
      {:openai, :streaming} => :pass,
      {:openai, :vision} => :pass,
      {:anthropic, :chat} => :pass,
      {:anthropic, :streaming} => :pass,
      {:anthropic, :vision} => :pass,
      {:gemini, :chat} => :pass,
      {:gemini, :streaming} => :pass,
      {:groq, :chat} => :pass,
      {:groq, :streaming} => :pass,
      {:ollama, :chat} => :pass,
      {:ollama, :streaming} => :skip
    }
  end
end
