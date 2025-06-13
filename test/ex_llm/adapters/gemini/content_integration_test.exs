defmodule ExLLM.Gemini.ContentIntegrationTest do
  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Content.{
    GenerateContentRequest,
    Part
  }
  alias ExLLM.Gemini.Content.Content, as: ContentStruct

  @moduletag :integration

  describe "generate_content/3 integration" do
    @tag :skip
    test "successfully generates content with valid API key" do
      # This test requires a valid GOOGLE_API_KEY environment variable
      model = "gemini-2.0-flash"
      request = %GenerateContentRequest{
        contents: [
          %ContentStruct{
            role: "user",
            parts: [%Part{text: "Say hello in one word"}]
          }
        ]
      }
      
      case ExLLM.Gemini.Content.generate_content(model, request) do
        {:ok, response} ->
          assert response.candidates
          assert length(response.candidates) > 0
          assert response.usage_metadata
          
        {:error, %{message: "API key not valid" <> _}} ->
          # Expected when running without valid API key
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end
end