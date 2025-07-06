defmodule ExLLM.CapabilityMatrixTest do
  use ExUnit.Case, async: true

  alias ExLLM.CapabilityMatrix

  describe "generate/0" do
    test "generates a complete capability matrix" do
      {:ok, matrix} = CapabilityMatrix.generate()

      assert is_map(matrix)
      assert is_list(matrix.providers)
      assert is_list(matrix.capabilities)
      assert is_map(matrix.matrix)

      # Check expected providers
      expected_providers = [
        :openai,
        :anthropic,
        :gemini,
        :groq,
        :ollama,
        :mistral,
        :xai,
        :perplexity
      ]

      assert Enum.sort(matrix.providers) == Enum.sort(expected_providers)

      # Check expected capabilities
      expected_capabilities = [:chat, :streaming, :models, :functions, :vision, :tools]
      assert matrix.capabilities == expected_capabilities

      # Verify matrix structure
      for provider <- matrix.providers do
        assert Map.has_key?(matrix.matrix, provider)
        provider_caps = matrix.matrix[provider]

        for capability <- matrix.capabilities do
          assert Map.has_key?(provider_caps, capability)
          status = provider_caps[capability]

          assert Map.has_key?(status, :indicator)
          assert Map.has_key?(status, :reason)
          assert status.indicator in ["✅", "❌", "⏭️", "❓"]
        end
      end
    end

    test "correctly maps capabilities" do
      {:ok, matrix} = CapabilityMatrix.generate()

      # Check some known capabilities
      openai_caps = matrix.matrix[:openai]
      assert openai_caps[:chat].indicator == "✅"
      assert openai_caps[:streaming].indicator == "✅"
      assert openai_caps[:vision].indicator == "✅"

      # Check provider without vision
      groq_caps = matrix.matrix[:groq]
      assert groq_caps[:chat].indicator == "✅"
      assert groq_caps[:vision].indicator == "❌"
    end

    test "handles unconfigured providers" do
      {:ok, matrix} = CapabilityMatrix.generate()

      # Find an unconfigured provider
      unconfigured =
        Enum.find(matrix.providers, fn provider ->
          not ExLLM.configured?(provider)
        end)

      if unconfigured do
        provider_caps = matrix.matrix[unconfigured]

        # Supported capabilities should show as skip if not configured
        supported_cap =
          Enum.find(matrix.capabilities, fn cap ->
            ExLLM.Capabilities.supports?(unconfigured, map_capability(cap))
          end)

        if supported_cap do
          assert provider_caps[supported_cap].indicator == "⏭️"
          assert provider_caps[supported_cap].reason =~ "No API key"
        end
      end
    end
  end

  describe "export/1" do
    test "exports to markdown format" do
      # Clean up any existing file
      File.rm("capability_matrix.md")

      {:ok, filename} = CapabilityMatrix.export(:markdown)
      assert filename == "capability_matrix.md"
      assert File.exists?(filename)

      content = File.read!(filename)

      # Check markdown structure
      assert content =~ "# Provider Capability Matrix"
      assert content =~ "| Provider |"
      assert content =~ "|----------|"
      assert content =~ "## Legend"

      # Check for providers
      assert content =~ "openai"
      assert content =~ "anthropic"
      assert content =~ "gemini"

      # Clean up
      File.rm!(filename)
    end

    test "exports to HTML format" do
      # Clean up any existing file
      File.rm("capability_matrix.html")

      {:ok, filename} = CapabilityMatrix.export(:html)
      assert filename == "capability_matrix.html"
      assert File.exists?(filename)

      content = File.read!(filename)

      # Check HTML structure
      assert content =~ "<title>ExLLM Provider Capability Matrix</title>"
      assert content =~ "<table>"
      assert content =~ "<th>Provider</th>"
      assert content =~ "class=\"pass\""
      assert content =~ "class=\"fail\""

      # Clean up
      File.rm!(filename)
    end
  end

  # Helper function matching the one in CapabilityMatrix
  defp map_capability(capability) do
    case capability do
      :models -> :list_models
      :functions -> :function_calling
      :tools -> :tool_use
      other -> other
    end
  end
end
