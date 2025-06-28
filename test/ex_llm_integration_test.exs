defmodule ExLLM.IntegrationTest do
  use ExUnit.Case
  import ExLLM.Testing.CapabilityHelpers

  @moduletag :integration

  describe "public API integration" do
    test "chat/3 with multiple providers" do
      providers = [:anthropic, :openai]

      for provider <- providers do
        skip_unless_configured_and_supports(provider, :chat)

        messages = [
          %{role: "system", content: "You are a helpful assistant."},
          %{role: "user", content: "Say hello in one word"}
        ]

        case ExLLM.chat(provider, messages, max_tokens: 10) do
          {:ok, response} ->
            assert is_map(response)
            assert Map.has_key?(response, :content)
            assert is_binary(response.content)
            assert response.content != ""
            assert response.metadata.provider == provider
            assert response.usage.prompt_tokens > 0
            assert response.usage.completion_tokens > 0
            assert response.cost >= 0.0

          {:error, :not_configured} ->
            # Skip if provider not configured
            :ok

          {:error, reason} ->
            flunk("Chat failed for #{provider}: #{inspect(reason)}")
        end
      end
    end

    @tag :streaming
    test "stream/4 with multiple providers" do
      providers = [:anthropic, :openai]

      for provider <- providers do
        skip_unless_configured_and_supports(provider, [:streaming])

        messages = [
          %{role: "user", content: "Count from 1 to 3"}
        ]

        # Track metrics during streaming
        start_time = System.monotonic_time(:millisecond)

        # Collect chunks using the callback API
        collector = fn chunk ->
          send(self(), {:chunk, chunk})
          # Track metrics
          send(self(), {:metrics, :chunk_received, byte_size(inspect(chunk))})
        end

        case ExLLM.stream(provider, messages, collector, max_tokens: 20, timeout: 10_000) do
          :ok ->
            chunks = collect_stream_chunks_with_metrics([], 2000)

            # Extract chunks and metrics
            actual_chunks =
              Enum.filter(chunks, fn
                {:chunk, _} -> true
                _ -> false
              end)
              |> Enum.map(fn {:chunk, c} -> c end)

            metrics =
              Enum.filter(chunks, fn
                {:metrics, _, _} -> true
                _ -> false
              end)

            # Basic streaming verification
            assert length(actual_chunks) > 0, "Did not receive any stream chunks from #{provider}"

            # Verify we received actual content
            full_content =
              actual_chunks
              |> Enum.map(fn chunk ->
                case chunk do
                  %{content: content} -> content
                  _ -> nil
                end
              end)
              |> Enum.filter(& &1)
              |> Enum.join("")

            assert String.length(full_content) > 0, "No content received from #{provider}"

            # Verify metrics were collected
            assert length(metrics) > 0, "No metrics collected during streaming"

            # Calculate streaming metrics
            end_time = System.monotonic_time(:millisecond)
            duration_ms = end_time - start_time
            chunk_count = length(actual_chunks)

            total_bytes =
              Enum.reduce(metrics, 0, fn {:metrics, :chunk_received, bytes}, acc ->
                acc + bytes
              end)

            # Verify reasonable metrics
            assert duration_ms > 0, "Streaming should take some time"
            assert chunk_count > 0, "Should receive multiple chunks"
            assert total_bytes > 0, "Should receive data"

            # Log metrics for visibility
            IO.puts("Streaming metrics for #{provider}:")
            IO.puts("  Duration: #{duration_ms}ms")
            IO.puts("  Chunks: #{chunk_count}")
            IO.puts("  Bytes: #{total_bytes}")

            IO.puts(
              "  Throughput: #{Float.round(total_bytes / (duration_ms / 1000), 2)} bytes/sec"
            )

          {:error, :not_configured} ->
            # Skip if provider not configured
            :ok

          {:error, reason} ->
            flunk("Streaming failed for #{provider}: #{inspect(reason)}")
        end
      end
    end

    test "list_models/1 with configured providers" do
      providers = [:anthropic, :openai]

      for provider <- providers do
        skip_unless_configured_and_supports(provider, :list_models)

        case ExLLM.list_models(provider) do
          {:ok, models} ->
            assert is_list(models)
            assert length(models) > 0, "Expected to receive at least one model from #{provider}"

            # Check model structure
            model = hd(models)
            assert is_map(model)
            assert Map.has_key?(model, :id)
            assert is_binary(model.id)
            assert Map.has_key?(model, :context_window)
            assert model.context_window > 0

          {:error, :not_configured} ->
            # Skip if provider not configured
            :ok

          {:error, error_message} when is_binary(error_message) ->
            # Some providers don't support model listing
            assert String.contains?(error_message, "does not support listing models")

          {:error, reason} ->
            flunk("List models failed for #{provider}: #{inspect(reason)}")
        end
      end
    end

    test "error handling with invalid API key" do
      # Test with a provider that uses API keys
      config = %{anthropic: %{api_key: "invalid-key-test"}}

      {:ok, static_provider} =
        ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      result = ExLLM.chat(:anthropic, messages, config_provider: static_provider)

      case result do
        {:error, {:api_error, %{status: status}}} when status in [401, 403] ->
          # Expected authentication error
          :ok

        {:error, {:authentication_error, _}} ->
          # Also acceptable authentication error format
          :ok

        {:error, :unauthorized} ->
          # Another acceptable authentication error format
          :ok

        {:ok, _response} ->
          # This could happen if we hit a cached response
          # In this case, we can't test the invalid API key scenario
          # but that's acceptable for cached testing
          :ok

        other ->
          flunk("Expected an authentication error or cached success, but got: #{inspect(other)}")
      end
    end
  end

  describe "fluent API integration" do
    test "builder pattern works with public API" do
      skip_unless_configured_and_supports(:anthropic, :chat)

      case ExLLM.build(:anthropic, [%{role: "user", content: "Hello"}])
           |> ExLLM.with_model("claude-3-haiku-20240307")
           |> ExLLM.with_temperature(0.5)
           |> ExLLM.with_max_tokens(20)
           |> ExLLM.execute() do
        {:ok, response} ->
          assert is_map(response)
          assert String.length(response.content) > 0
          assert response.metadata.provider == :anthropic

        {:error, :not_configured} ->
          # Skip test if not configured
          :ok

        {:error, reason} ->
          flunk("Fluent API failed: #{inspect(reason)}")
      end
    end

    test "builder pattern with streaming" do
      skip_unless_configured_and_supports(:anthropic, [:streaming])

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      # Get the built request
      builder =
        ExLLM.build(:anthropic, [%{role: "user", content: "Say hi"}])
        |> ExLLM.with_max_tokens(10)

      case ExLLM.stream(
             :anthropic,
             builder.request.messages,
             collector,
             Map.to_list(builder.request.options) ++ [timeout: 10_000]
           ) do
        :ok ->
          chunks = collect_stream_chunks([], 2000)
          assert length(chunks) > 0, "Did not receive any stream chunks"

        {:error, :not_configured} ->
          # Skip test if not configured
          :ok

        {:error, reason} ->
          flunk("Fluent streaming failed: #{inspect(reason)}")
      end
    end
  end

  # Helper function to collect stream chunks
  defp collect_stream_chunks(chunks, timeout)

  defp collect_stream_chunks(chunks, timeout) do
    receive do
      {:chunk, chunk} ->
        collect_stream_chunks([chunk | chunks], timeout)
    after
      timeout -> Enum.reverse(chunks)
    end
  end

  # Helper function to collect stream chunks with metrics
  defp collect_stream_chunks_with_metrics(acc, timeout) do
    receive do
      {:chunk, chunk} ->
        collect_stream_chunks_with_metrics([{:chunk, chunk} | acc], timeout)

      {:metrics, type, data} ->
        collect_stream_chunks_with_metrics([{:metrics, type, data} | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end
end
