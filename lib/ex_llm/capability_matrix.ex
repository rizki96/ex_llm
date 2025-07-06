defmodule ExLLM.CapabilityMatrix do
  @moduledoc """
  Provider Capability Matrix generator for ExLLM.

  Displays a comprehensive matrix showing which providers support which capabilities,
  with status indicators based on test results and configuration.

  ## Usage

      # Display the capability matrix
      ExLLM.CapabilityMatrix.display()
      
      # Get the matrix as data
      {:ok, matrix} = ExLLM.CapabilityMatrix.generate()
      
      # Export to different formats
      ExLLM.CapabilityMatrix.export(:markdown)
      ExLLM.CapabilityMatrix.export(:html)
  """

  alias ExLLM.Capabilities

  # Core capabilities to track in the matrix
  @core_capabilities [:chat, :streaming, :models, :functions, :vision, :tools]

  # Status indicators
  @status_pass "✅"
  @status_fail "❌"
  @status_skip "⏭️"
  @status_unknown "❓"

  @doc """
  Generate the capability matrix data structure.

  Returns a map with:
  - `:providers` - List of provider atoms
  - `:capabilities` - List of capability atoms
  - `:matrix` - Nested map of provider -> capability -> status
  """
  def generate do
    providers = get_providers()
    capabilities = @core_capabilities

    matrix =
      for provider <- providers, into: %{} do
        provider_capabilities =
          for capability <- capabilities, into: %{} do
            status = determine_status(provider, capability)
            {capability, status}
          end

        {provider, provider_capabilities}
      end

    {:ok,
     %{
       providers: providers,
       capabilities: capabilities,
       matrix: matrix
     }}
  end

  @doc """
  Display the capability matrix in a formatted table.
  """
  def display do
    {:ok, data} = generate()

    # Header
    IO.puts("\nProvider Capability Matrix")
    IO.puts("========================\n")

    # Table header
    header = ["Provider" | Enum.map(data.capabilities, &format_capability/1)]
    col_widths = calculate_column_widths(header, data)

    # Print header
    print_row(header, col_widths)
    print_separator(col_widths)

    # Print each provider row
    for provider <- data.providers do
      row = [
        format_provider(provider)
        | Enum.map(data.capabilities, fn cap ->
            data.matrix[provider][cap].indicator
          end)
      ]

      print_row(row, col_widths)
    end

    # Legend
    IO.puts("\nLegend:")
    IO.puts("#{@status_pass} Pass - Feature supported and working")
    IO.puts("#{@status_fail} Fail - Feature not supported or failing")
    IO.puts("#{@status_skip} Skip - Feature not tested (no API key)")
    IO.puts("#{@status_unknown} Unknown - No data available")

    :ok
  end

  @doc """
  Export the capability matrix in different formats.
  """
  def export(:markdown) do
    {:ok, data} = generate()

    lines = [
      "# Provider Capability Matrix\n",
      "| Provider | " <> Enum.map_join(data.capabilities, " | ", &to_string/1) <> " |",
      "|----------|" <> String.duplicate("---------|", length(data.capabilities))
    ]

    provider_lines =
      for provider <- data.providers do
        "| #{provider} | " <>
          Enum.map_join(data.capabilities, " | ", fn cap ->
            data.matrix[provider][cap].indicator
          end) <> " |"
      end

    legend = [
      "\n## Legend",
      "- #{@status_pass} Pass - Feature supported and working",
      "- #{@status_fail} Fail - Feature not supported or failing",
      "- #{@status_skip} Skip - Feature not tested (no API key)",
      "- #{@status_unknown} Unknown - No data available"
    ]

    content = Enum.join(lines ++ provider_lines ++ legend, "\n")

    File.write!("capability_matrix.md", content)
    {:ok, "capability_matrix.md"}
  end

  def export(:html) do
    {:ok, data} = generate()

    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>ExLLM Provider Capability Matrix</title>
      <style>
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: center; }
        th { background-color: #f2f2f2; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: orange; }
        .unknown { color: gray; }
      </style>
    </head>
    <body>
      <h1>ExLLM Provider Capability Matrix</h1>
      <table>
        <tr>
          <th>Provider</th>
          #{Enum.map_join(data.capabilities, "", fn cap -> "<th>#{cap}</th>" end)}
        </tr>
        #{generate_html_rows(data)}
      </table>
      #{generate_html_legend()}
    </body>
    </html>
    """

    File.write!("capability_matrix.html", html)
    {:ok, "capability_matrix.html"}
  end

  # Private functions

  defp get_providers do
    [:openai, :anthropic, :gemini, :groq, :ollama, :mistral, :xai, :perplexity]
  end

  defp determine_status(provider, capability) do
    cond do
      # Check if provider supports the capability according to static config
      not Capabilities.supports?(provider, map_capability(capability)) ->
        %{indicator: @status_fail, reason: "Not supported"}

      # Check if provider is configured (has API key)
      not ExLLM.configured?(provider) ->
        %{indicator: @status_skip, reason: "No API key configured"}

      # Check actual implementation and test results
      true ->
        check_implementation_status(provider, capability)
    end
  end

  defp map_capability(capability) do
    # Map our matrix capabilities to internal capability atoms
    case capability do
      :models -> :list_models
      :functions -> :function_calling
      :tools -> :tool_use
      other -> other
    end
  end

  defp check_implementation_status(provider, capability) do
    internal_cap = map_capability(capability)

    # First check test results if available
    test_status = ExLLM.TestResultAggregator.get_test_status(provider, internal_cap)

    case test_status do
      :passed ->
        %{indicator: @status_pass, reason: "Tests passed"}

      :failed ->
        %{indicator: @status_fail, reason: "Tests failed"}

      :skipped ->
        %{indicator: @status_skip, reason: "Tests skipped"}

      :not_tested ->
        # Fall back to capability configuration
        if Capabilities.supports?(provider, internal_cap) do
          %{indicator: @status_pass, reason: "Supported (not tested)"}
        else
          %{indicator: @status_unknown, reason: "Status unknown"}
        end
    end
  end

  defp format_capability(cap) do
    cap |> to_string() |> String.capitalize()
  end

  defp format_provider(provider) do
    provider |> to_string() |> String.capitalize()
  end

  defp calculate_column_widths(header, data) do
    # Calculate the width needed for each column
    header_widths = Enum.map(header, &String.length/1)

    # Check provider name lengths
    provider_widths = [
      Enum.map(data.providers, fn p ->
        p |> format_provider() |> String.length()
      end)
      |> Enum.max()
    ]

    # Capability columns are fixed width (for status indicators)
    capability_widths = List.duplicate(8, length(data.capabilities))

    # Combine to get final widths
    [max_width(hd(header_widths), hd(provider_widths)) | capability_widths]
  end

  defp print_row(row, widths) do
    formatted =
      row
      |> Enum.zip(widths)
      |> Enum.map(fn {cell, width} ->
        String.pad_trailing(to_string(cell), width)
      end)
      |> Enum.join(" | ")

    IO.puts("| #{formatted} |")
  end

  defp print_separator(widths) do
    separators = Enum.map(widths, fn w -> String.duplicate("-", w) end)
    IO.puts("|" <> Enum.map_join(separators, "|", fn s -> "-#{s}-" end) <> "|")
  end

  defp generate_html_rows(data) do
    Enum.map_join(data.providers, "\n", fn provider ->
      """
      <tr>
        <td>#{format_provider(provider)}</td>
        #{Enum.map_join(data.capabilities, "", fn cap ->
        status = data.matrix[provider][cap]
        class = status_to_class(status.indicator)
        "<td class=\"#{class}\" title=\"#{status.reason}\">#{status.indicator}</td>"
      end)}
      </tr>
      """
    end)
  end

  defp generate_html_legend do
    """
    <div style="margin-top: 20px;">
      <h3>Legend</h3>
      <ul>
        <li><span class="pass">#{@status_pass}</span> Pass - Feature supported and working</li>
        <li><span class="fail">#{@status_fail}</span> Fail - Feature not supported or failing</li>
        <li><span class="skip">#{@status_skip}</span> Skip - Feature not tested (no API key)</li>
        <li><span class="unknown">#{@status_unknown}</span> Unknown - No data available</li>
      </ul>
    </div>
    """
  end

  defp status_to_class(indicator) do
    case indicator do
      @status_pass -> "pass"
      @status_fail -> "fail"
      @status_skip -> "skip"
      @status_unknown -> "unknown"
    end
  end

  defp max_width(a, b) when a > b, do: a
  defp max_width(_, b), do: b
end
