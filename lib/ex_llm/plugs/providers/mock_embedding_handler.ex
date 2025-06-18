defmodule ExLLM.Plugs.Providers.MockEmbeddingHandler do
  @moduledoc """
  Mock handler for embedding requests in the pipeline architecture.

  This handler simulates embedding generation for testing purposes.
  """

  use ExLLM.Plug

  alias ExLLM.Types.EmbeddingResponse

  @impl true
  def call(%ExLLM.Pipeline.Request{} = request, opts) do
    # Get input from the request
    input = get_input_from_request(request)

    # Check if we should simulate an error
    if error = get_mock_error(request.config, opts) do
      ExLLM.Pipeline.Request.halt_with_error(request, %{
        error: error,
        plug: __MODULE__,
        mock_embedding_handler_called: true
      })
    else
      # Check for application environment mock response first
      case Application.get_env(:ex_llm, :mock_responses, %{})[:embeddings] do
        %EmbeddingResponse{} = response ->
          # Use the configured mock response
          embedding_response = response

          request
          |> Map.put(:result, embedding_response)
          |> ExLLM.Pipeline.Request.put_state(:completed)
          |> ExLLM.Pipeline.Request.assign(:mock_embedding_handler_called, true)

        {:error, message} ->
          # Return configured error
          ExLLM.Pipeline.Request.halt_with_error(request, %{
            error: message,
            plug: __MODULE__,
            mock_embedding_handler_called: true
          })

        nil ->
          # Generate mock embeddings
          embeddings = generate_mock_embeddings(input)

          embedding_response = %EmbeddingResponse{
            embeddings: embeddings,
            model: request.config[:model] || "mock-embedding-model",
            usage: %{
              input_tokens: estimate_tokens(input),
              output_tokens: 0,
              total_tokens: estimate_tokens(input)
            },
            metadata: %{
              provider: :mock,
              mock_handler_called: true
            }
          }

          request
          |> Map.put(:result, embedding_response)
          |> ExLLM.Pipeline.Request.put_state(:completed)
          |> ExLLM.Pipeline.Request.assign(:mock_embedding_handler_called, true)
      end
    end
  end

  defp get_input_from_request(request) do
    cond do
      request.assigns[:embedding_input] ->
        request.assigns[:embedding_input]

      request.options[:input] ->
        request.options[:input]

      # Check application environment for test data
      app_input = Application.get_env(:ex_llm, :mock_embedding_input) ->
        app_input

      true ->
        ["mock embedding input"]
    end
  end

  defp get_mock_error(config, opts) do
    # Check for mock error in config, opts, or application environment
    error =
      config[:mock_error] || opts[:error] ||
        Application.get_env(:ex_llm, :mock_embedding_error)

    # Handle case where the error might be returned from the App.env mock responses
    case error do
      {:error, message} when is_binary(message) -> message
      error -> error
    end
  end

  defp generate_mock_embeddings(input) when is_binary(input) do
    [generate_mock_embedding(input)]
  end

  defp generate_mock_embeddings(input) when is_list(input) do
    Enum.map(input, &generate_mock_embedding/1)
  end

  defp generate_mock_embedding(text) when is_binary(text) do
    # Generate a deterministic mock embedding based on text content
    # This creates a 384-dimensional vector with some semantic meaning

    # Hash the text to get consistent values
    hash = :crypto.hash(:md5, text) |> :binary.bin_to_list()

    # Create base embedding
    embedding = List.duplicate(0.0, 384)

    # Add some values based on text characteristics
    embedding
    |> add_text_features(text, hash)
    |> normalize_vector()
  end

  defp add_text_features(embedding, text, hash) do
    text_length = String.length(text)
    word_count = text |> String.split() |> length()

    # Use hash values to set embedding dimensions
    embedding
    |> List.update_at(0, fn _ -> (Enum.at(hash, 0) - 128) / 128.0 end)
    |> List.update_at(1, fn _ -> (Enum.at(hash, 1) - 128) / 128.0 end)
    |> List.update_at(2, fn _ -> text_length / 1000.0 end)
    |> List.update_at(3, fn _ -> word_count / 100.0 end)
    # Fill more dimensions with hash-based values
    |> fill_remaining_dimensions(hash)
  end

  defp fill_remaining_dimensions(embedding, hash) do
    hash_cycle = Stream.cycle(hash)

    embedding
    |> Enum.with_index()
    |> Enum.map(fn {val, idx} ->
      if idx < 4 do
        # Keep the first 4 values we set
        val
      else
        # Use hash values with some variation
        hash_val = Enum.at(hash_cycle, idx)
        # Scale down for realistic values
        (hash_val - 128) / 128.0 * 0.1
      end
    end)
  end

  defp normalize_vector(vector) do
    # L2 normalization
    magnitude =
      vector
      |> Enum.map(&(&1 * &1))
      |> Enum.sum()
      |> :math.sqrt()

    if magnitude > 0 do
      Enum.map(vector, &(&1 / magnitude))
    else
      vector
    end
  end

  defp estimate_tokens(input) when is_binary(input) do
    # Simple estimation: ~4 characters per token
    div(String.length(input), 4) + 1
  end

  defp estimate_tokens(input) when is_list(input) do
    input
    |> Enum.map(&estimate_tokens/1)
    |> Enum.sum()
  end

  defp estimate_tokens(_), do: 1
end
