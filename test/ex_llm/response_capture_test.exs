defmodule ExLLM.ResponseCaptureTest do
  use ExUnit.Case, async: false

  @moduletag :unit
  alias ExLLM.ResponseCapture
  alias ExLLM.Testing.LiveApiCacheStorage

  setup do
    # Ensure test cache is enabled for these tests
    original_cache_enabled = System.get_env("EX_LLM_TEST_CACHE_ENABLED")
    System.put_env("EX_LLM_TEST_CACHE_ENABLED", "true")

    # Clean up any existing captures
    on_exit(fn ->
      System.delete_env("EX_LLM_CAPTURE_RESPONSES")
      System.delete_env("EX_LLM_SHOW_CAPTURED")

      # Restore original cache setting
      if original_cache_enabled do
        System.put_env("EX_LLM_TEST_CACHE_ENABLED", original_cache_enabled)
      else
        System.delete_env("EX_LLM_TEST_CACHE_ENABLED")
      end
    end)

    :ok
  end

  describe "enabled?/0" do
    test "returns true when environment variable is set to true" do
      System.put_env("EX_LLM_CAPTURE_RESPONSES", "true")
      assert ResponseCapture.enabled?()
    end

    test "returns false when environment variable is not set" do
      System.delete_env("EX_LLM_CAPTURE_RESPONSES")
      refute ResponseCapture.enabled?()
    end

    test "returns false when environment variable is set to false" do
      System.put_env("EX_LLM_CAPTURE_RESPONSES", "false")
      refute ResponseCapture.enabled?()
    end
  end

  describe "display_enabled?/0" do
    test "returns true when environment variable is set to true" do
      System.put_env("EX_LLM_SHOW_CAPTURED", "true")
      assert ResponseCapture.display_enabled?()
    end

    test "returns false when environment variable is not set" do
      System.delete_env("EX_LLM_SHOW_CAPTURED")
      refute ResponseCapture.display_enabled?()
    end
  end

  describe "capture_response/5" do
    test "captures response when enabled" do
      System.put_env("EX_LLM_CAPTURE_RESPONSES", "true")
      System.put_env("EX_LLM_SHOW_CAPTURED", "false")

      provider = :test_openai_capture
      endpoint = "/v1/chat/completions/test_capture"

      request = %{
        model: "gpt-4",
        messages: [%{role: "user", content: "Hello"}],
        temperature: 0.7,
        max_tokens: 100
      }

      response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1_234_567_890,
        "model" => "gpt-4",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! How can I help you today?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 8,
          "total_tokens" => 18
        }
      }

      metadata = %{
        "response_time_ms" => 523,
        "status_code" => 200
      }

      # Capture the response
      assert :ok =
               ResponseCapture.capture_response(provider, endpoint, request, response, metadata)

      # Wait a bit longer for async storage
      Process.sleep(200)

      # Verify it was stored
      keys = LiveApiCacheStorage.list_cache_keys()

      capture_key =
        Enum.find(keys, fn key ->
          String.contains?(key, Atom.to_string(provider)) and
            String.contains?(key, endpoint)
        end)

      assert capture_key != nil

      # Verify stored data
      # LiveApiCacheStorage.get returns just the response_data, not the full entry
      case LiveApiCacheStorage.get(capture_key) do
        {:ok, stored_response} ->
          # The response data should match what we stored
          assert stored_response == response

        other ->
          flunk("Failed to get cached data: #{inspect(other)}")
      end
    end

    test "skips capture when disabled" do
      System.put_env("EX_LLM_CAPTURE_RESPONSES", "false")

      # Note the initial count of keys
      initial_keys =
        LiveApiCacheStorage.list_cache_keys()
        |> Enum.filter(fn key ->
          String.contains?(key, "test_provider") && String.contains?(key, "/test/endpoint")
        end)
        |> length()

      # Capture attempt with unique provider/endpoint
      assert :ok =
               ResponseCapture.capture_response(:test_provider, "/test/endpoint", %{}, %{}, %{})

      # Wait a bit
      Process.sleep(100)

      # Verify nothing new was stored
      final_keys =
        LiveApiCacheStorage.list_cache_keys()
        |> Enum.filter(fn key ->
          String.contains?(key, "test_provider") && String.contains?(key, "/test/endpoint")
        end)
        |> length()

      assert final_keys == initial_keys
    end

    test "displays capture when display is enabled" do
      System.put_env("EX_LLM_CAPTURE_RESPONSES", "true")
      System.put_env("EX_LLM_SHOW_CAPTURED", "true")

      # Capture output
      captured_output =
        ExUnit.CaptureIO.capture_io(fn ->
          ResponseCapture.capture_response(
            :test_openai_display,
            "/v1/chat/completions/test_display",
            %{model: "gpt-4"},
            %{
              "choices" => [
                %{
                  "message" => %{"content" => "Test response"},
                  "finish_reason" => "stop"
                }
              ],
              "usage" => %{
                "prompt_tokens" => 10,
                "completion_tokens" => 5,
                "total_tokens" => 15
              }
            },
            %{"response_time_ms" => 123}
          )

          # Wait for async display
          Process.sleep(100)
        end)

      # Verify display output - the output contains ANSI codes
      assert captured_output =~ "CAPTURED RESPONSE"
      # Provider name appears in output
      assert captured_output =~ "openai"
      # Duration appears
      assert captured_output =~ "123ms"
      assert captured_output =~ "Test response"
      assert captured_output =~ "10 in / 5 out / 15 total"
    end
  end
end
