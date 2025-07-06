defmodule ExLLM.Testing.CapabilityMatrix do
  @moduledoc """
  Generates a provider capability matrix showing which providers support which features.

  This module provides functionality to:
  - Display a visual matrix of provider capabilities
  - Export the matrix in various formats (console, markdown, HTML)
  - Integrate with test results to show actual vs configured capabilities
  - Support both core and extended capability sets
  """

  alias ExLLM.Capabilities

  @core_capabilities [:chat, :streaming, :list_models, :function_calling, :vision, :embeddings]

  @all_providers [
    :openai,
    :anthropic,
    :gemini,
    :groq,
    :ollama,
    :mistral,
    :xai,
    :perplexity,
    :openrouter,
    :lmstudio,
    :bumblebee,
    :mock
  ]

  @doc """
  Generates and displays the capability matrix in the console.

  ## Options
    - `:providers` - List of providers to include (defaults to all)
    - `:capabilities` - List of capabilities to show (defaults to core)
    - `:extended` - Boolean to show all capabilities (defaults to false)
    - `:test_results` - Map of test results to overlay on capabilities
  """
  def display(opts \\ []) do
    matrix = generate_matrix(opts)
    print_console_matrix(matrix, opts)
  end

  @doc """
  Generates the capability matrix and returns it as a data structure.

  Returns a map with:
    - `:providers` - List of providers included
    - `:capabilities` - List of capabilities checked
    - `:matrix` - Map of {provider, capability} => status
    - `:metadata` - Additional information about the matrix
  """
  def generate_matrix(opts \\ []) do
    providers = Keyword.get(opts, :providers, available_providers())
    capabilities = get_capabilities_list(opts)
    test_results = Keyword.get(opts, :test_results, %{})

    matrix_data =
      for provider <- providers,
          capability <- capabilities,
          into: %{} do
        status = get_capability_status(provider, capability, test_results)
        {{provider, capability}, status}
      end

    %{
      providers: providers,
      capabilities: capabilities,
      matrix: matrix_data,
      metadata: %{
        generated_at: DateTime.utc_now(),
        total_capabilities: length(providers) * length(capabilities),
        supported_count: count_supported(matrix_data),
        test_integration: map_size(test_results) > 0
      }
    }
  end

  @doc """
  Exports the capability matrix to a markdown file.
  """
  def export_markdown(opts \\ []) do
    matrix = generate_matrix(opts)
    content = format_as_markdown(matrix)

    filename = Keyword.get(opts, :output, "capability_matrix.md")
    File.write!(filename, content)

    {:ok, filename}
  end

  @doc """
  Exports the capability matrix to an HTML file with styling.
  """
  def export_html(opts \\ []) do
    matrix = generate_matrix(opts)
    content = format_as_html(matrix)

    filename = Keyword.get(opts, :output, "capability_matrix.html")
    File.write!(filename, content)

    {:ok, filename}
  end

  # Private functions

  defp available_providers do
    # Get providers that have capabilities defined
    configured =
      @all_providers
      |> Enum.filter(fn provider ->
        # Check if provider has any capabilities defined
        capabilities = Capabilities.get_capabilities(provider)
        capabilities != nil && capabilities != []
      end)

    # Ensure we have at least the major providers
    major_providers = [:openai, :anthropic, :gemini, :groq, :ollama]
    Enum.uniq(configured ++ major_providers)
  end

  defp get_capabilities_list(opts) do
    cond do
      Keyword.get(opts, :extended, false) ->
        all_capabilities()

      caps = Keyword.get(opts, :capabilities) ->
        caps

      true ->
        @core_capabilities
    end
  end

  defp all_capabilities do
    # Get all unique capabilities from the Capabilities module
    Capabilities.supported_capabilities()
    |> Enum.sort()
  end

  defp get_capability_status(provider, capability, test_results) do
    test_key = {provider, capability}

    cond do
      # First check test results if available
      Map.has_key?(test_results, test_key) ->
        case Map.get(test_results, test_key) do
          :pass -> :pass
          :fail -> :fail
          :skip -> :skip
          _ -> :unknown
        end

      # Then check configured capabilities
      Capabilities.supports?(provider, capability) ->
        :configured

      # Provider not configured
      not provider_configured?(provider) ->
        :not_configured

      # Capability not supported
      true ->
        :not_supported
    end
  end

  defp provider_configured?(provider) do
    config = ExLLM.Environment.provider_config(provider)
    config[:api_key] != nil || provider in [:ollama, :lmstudio, :bumblebee]
  end

  defp count_supported(matrix_data) do
    Enum.count(matrix_data, fn {_, status} ->
      status in [:pass, :configured]
    end)
  end

  defp print_console_matrix(matrix, _opts) do
    IO.puts("\n#{IO.ANSI.bright()}=== Provider Capability Matrix ===#{IO.ANSI.reset()}\n")

    # Header row
    IO.write(String.pad_trailing("Capability", 15))

    Enum.each(matrix.providers, fn provider ->
      IO.write(String.pad_trailing(to_string(provider), 12))
    end)

    IO.puts("\n" <> String.duplicate("-", 15 + length(matrix.providers) * 12))

    # Data rows
    Enum.each(matrix.capabilities, fn capability ->
      IO.write(String.pad_trailing(to_string(capability), 15))

      Enum.each(matrix.providers, fn provider ->
        status = Map.get(matrix.matrix, {provider, capability}, :unknown)
        {symbol, color} = format_status(status)
        IO.write(color <> String.pad_trailing(symbol, 12) <> IO.ANSI.reset())
      end)

      IO.puts("")
    end)

    # Legend
    IO.puts("\n#{IO.ANSI.light_black()}Legend:")

    IO.puts(
      "  ✅ Pass (test verified) | ✓ Configured | ❌ Fail | ⏭️ Skip | ❓ Unknown | - Not supported#{IO.ANSI.reset()}"
    )

    # Summary
    if matrix.metadata.test_integration do
      IO.puts("\n#{IO.ANSI.cyan()}Test results integrated: Yes#{IO.ANSI.reset()}")
    end

    supported = matrix.metadata.supported_count
    total = matrix.metadata.total_capabilities
    percentage = round(supported / total * 100)

    IO.puts("Total coverage: #{supported}/#{total} (#{percentage}%)")
  end

  defp format_status(status) do
    case status do
      :pass -> {"✅", IO.ANSI.green()}
      :configured -> {"✓", IO.ANSI.green()}
      :fail -> {"❌", IO.ANSI.red()}
      :skip -> {"⏭️", IO.ANSI.yellow()}
      :not_configured -> {"○", IO.ANSI.light_black()}
      :not_supported -> {"-", IO.ANSI.light_black()}
      _ -> {"❓", IO.ANSI.light_black()}
    end
  end

  defp format_as_markdown(matrix) do
    """
    # Provider Capability Matrix

    Generated: #{DateTime.utc_now() |> DateTime.to_string()}

    | Capability | #{Enum.map_join(matrix.providers, " | ", &to_string/1)} |
    |------------|#{String.duplicate("------|", length(matrix.providers))}
    #{format_markdown_rows(matrix)}

    ## Legend
    - ✅ Pass - Verified by tests
    - ✓ Configured - Available per configuration
    - ❌ Fail - Test failed
    - ⏭️ Skip - Test skipped
    - ○ Not configured - Provider not set up
    - - Not supported - Feature not available
    - ❓ Unknown - Status unclear

    ## Summary
    - Total capabilities checked: #{matrix.metadata.total_capabilities}
    - Supported capabilities: #{matrix.metadata.supported_count}
    - Coverage: #{round(matrix.metadata.supported_count / matrix.metadata.total_capabilities * 100)}%
    #{if matrix.metadata.test_integration, do: "- Test results: Integrated", else: "- Test results: Not available"}
    """
  end

  defp format_markdown_rows(matrix) do
    matrix.capabilities
    |> Enum.map(fn capability ->
      cells =
        matrix.providers
        |> Enum.map(fn provider ->
          status = Map.get(matrix.matrix, {provider, capability}, :unknown)
          {symbol, _} = format_status(status)
          symbol
        end)
        |> Enum.join(" | ")

      "| #{capability} | #{cells} |"
    end)
    |> Enum.join("\n")
  end

  defp format_as_html(matrix) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>ExLLM Provider Capability Matrix</title>
      <style>
        body { font-family: system-ui, -apple-system, sans-serif; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 8px 12px; text-align: center; border: 1px solid #ddd; }
        th { background: #f5f5f5; font-weight: 600; }
        .capability { text-align: left; font-weight: 500; }
        .pass { color: #22c55e; }
        .configured { color: #16a34a; }
        .fail { color: #ef4444; }
        .skip { color: #eab308; }
        .not-configured { color: #9ca3af; }
        .not-supported { color: #d1d5db; }
        .unknown { color: #6b7280; }
        .legend { margin-top: 20px; }
        .legend-item { display: inline-block; margin-right: 20px; }
        .summary { margin-top: 20px; padding: 15px; background: #f9fafb; border-radius: 5px; }
      </style>
    </head>
    <body>
      <h1>ExLLM Provider Capability Matrix</h1>
      <p>Generated: #{DateTime.utc_now() |> DateTime.to_string()}</p>
      
      <table>
        <thead>
          <tr>
            <th>Capability</th>
            #{format_html_headers(matrix.providers)}
          </tr>
        </thead>
        <tbody>
          #{format_html_rows(matrix)}
        </tbody>
      </table>
      
      <div class="legend">
        <h3>Legend</h3>
        <span class="legend-item pass">✅ Pass</span>
        <span class="legend-item configured">✓ Configured</span>
        <span class="legend-item fail">❌ Fail</span>
        <span class="legend-item skip">⏭️ Skip</span>
        <span class="legend-item not-configured">○ Not configured</span>
        <span class="legend-item not-supported">- Not supported</span>
        <span class="legend-item unknown">❓ Unknown</span>
      </div>
      
      <div class="summary">
        <h3>Summary</h3>
        <p>Total capabilities: #{matrix.metadata.total_capabilities}</p>
        <p>Supported: #{matrix.metadata.supported_count}</p>
        <p>Coverage: #{round(matrix.metadata.supported_count / matrix.metadata.total_capabilities * 100)}%</p>
        #{if matrix.metadata.test_integration, do: "<p>Test results: Integrated</p>", else: ""}
      </div>
    </body>
    </html>
    """
  end

  defp format_html_headers(providers) do
    providers
    |> Enum.map(fn provider -> "<th>#{provider}</th>" end)
    |> Enum.join("\n            ")
  end

  defp format_html_rows(matrix) do
    matrix.capabilities
    |> Enum.map(fn capability ->
      cells =
        matrix.providers
        |> Enum.map(fn provider ->
          status = Map.get(matrix.matrix, {provider, capability}, :unknown)
          {symbol, _} = format_status(status)
          css_class = to_string(status) |> String.replace("_", "-")
          "<td class=\"#{css_class}\">#{symbol}</td>"
        end)
        |> Enum.join("\n            ")

      """
          <tr>
            <td class="capability">#{capability}</td>
            #{cells}
          </tr>
      """
    end)
    |> Enum.join("")
  end
end
