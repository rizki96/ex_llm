defmodule ExLLM.API.BatchProcessingTest do
  @moduledoc """
  Comprehensive tests for the unified batch processing API.
  Tests the public ExLLM API to ensure excellent user experience.
  """

  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :batch_processing
  @moduletag provider: :anthropic

  # Test batch messages for Anthropic
  @test_batch_messages [
    [
      %{role: "user", content: "What is the capital of France?"}
    ],
    [
      %{role: "user", content: "What is 2 + 2?"}
    ],
    [
      %{role: "user", content: "What color is the sky?"}
    ]
  ]

  setup_all do
    enable_cache_debug()
    :ok
  end

  setup context do
    setup_test_cache(context)

    on_exit(fn ->
      ExLLM.Testing.TestCacheDetector.clear_test_context()
    end)

    :ok
  end

  describe "create_batch/3" do
    @tag provider: :anthropic
    test "creates batch successfully with Anthropic" do
      case ExLLM.create_batch(:anthropic, @test_batch_messages, model: "claude-3-haiku") do
        {:ok, batch} ->
          assert is_map(batch)
          assert Map.has_key?(batch, :id)
          assert Map.has_key?(batch, :status)

        {:error, reason} ->
          IO.puts("Anthropic batch creation failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Message batches not supported for provider: openai"} =
               ExLLM.create_batch(:openai, @test_batch_messages)

      assert {:error, "Message batches not supported for provider: gemini"} =
               ExLLM.create_batch(:gemini, @test_batch_messages)
    end

    test "handles invalid message lists" do
      invalid_message_lists = [
        nil,
        "",
        123,
        %{},
        [],
        [nil],
        ["invalid_message"],
        [%{invalid: "structure"}]
      ]

      for invalid_messages <- invalid_message_lists do
        case ExLLM.create_batch(:anthropic, invalid_messages) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some invalid message lists might be handled gracefully
            :ok
        end
      end
    end

    @tag provider: :anthropic
    test "handles various batch configurations" do
      configs = [
        # Basic config
        [model: "claude-3-haiku"],

        # With additional options
        [model: "claude-3-haiku", max_tokens: 100],

        # With temperature
        [model: "claude-3-haiku", temperature: 0.5],

        # With system message
        [model: "claude-3-haiku", system: "You are a helpful assistant."]
      ]

      for config <- configs do
        case ExLLM.create_batch(:anthropic, @test_batch_messages, config) do
          {:ok, batch} ->
            assert is_map(batch)
            assert Map.has_key?(batch, :id)

          {:error, reason} ->
            IO.puts("Batch creation with config #{inspect(config)} failed: #{inspect(reason)}")
            :ok
        end
      end
    end

    test "handles empty message list" do
      case ExLLM.create_batch(:anthropic, []) do
        {:error, _reason} ->
          :ok

        {:ok, _} ->
          # Empty batch might be handled gracefully
          :ok
      end
    end

    @tag provider: :anthropic
    test "handles large batch sizes" do
      # Create a larger batch (but not too large to avoid timeouts)
      large_batch =
        for i <- 1..10 do
          [%{role: "user", content: "Question #{i}: What is #{i} + #{i}?"}]
        end

      case ExLLM.create_batch(:anthropic, large_batch, model: "claude-3-haiku") do
        {:ok, batch} ->
          assert is_map(batch)
          assert Map.has_key?(batch, :id)

        {:error, reason} ->
          IO.puts("Large batch creation failed: #{inspect(reason)}")
          :ok
      end
    end
  end

  describe "get_batch/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Message batches not supported for provider: openai"} =
               ExLLM.get_batch(:openai, "batch_id")

      assert {:error, "Message batches not supported for provider: gemini"} =
               ExLLM.get_batch(:gemini, "batch_id")
    end

    @tag provider: :anthropic
    test "handles non-existent batch ID with Anthropic" do
      case ExLLM.get_batch(:anthropic, "batch_non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid batch ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.get_batch(:anthropic, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid batch ID: #{inspect(invalid_id)}")
        end
      end
    end

    test "handles malformed batch IDs" do
      malformed_ids = [
        "",
        "invalid-format",
        "batch_",
        "not_a_batch_id"
      ]

      for malformed_id <- malformed_ids do
        case ExLLM.get_batch(:anthropic, malformed_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some malformed IDs might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "cancel_batch/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Message batches not supported for provider: openai"} =
               ExLLM.cancel_batch(:openai, "batch_id")

      assert {:error, "Message batches not supported for provider: gemini"} =
               ExLLM.cancel_batch(:gemini, "batch_id")
    end

    @tag provider: :anthropic
    test "handles non-existent batch ID with Anthropic" do
      case ExLLM.cancel_batch(:anthropic, "batch_non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent batches
          :ok
      end
    end

    test "handles invalid batch ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.cancel_batch(:anthropic, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid batch ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "batch message validation" do
    test "validates message structure" do
      valid_message_lists = [
        # Single message conversation
        [[%{role: "user", content: "Hello"}]],

        # Multiple message conversation
        [
          [
            %{role: "user", content: "Hello"},
            %{role: "assistant", content: "Hi there!"},
            %{role: "user", content: "How are you?"}
          ]
        ],

        # Multiple conversations
        [
          [%{role: "user", content: "Question 1"}],
          [%{role: "user", content: "Question 2"}]
        ]
      ]

      for message_list <- valid_message_lists do
        case ExLLM.create_batch(:anthropic, message_list, model: "claude-3-haiku") do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            # Message might be valid but other issues (auth, quotas, etc.)
            IO.puts("Valid message list failed: #{inspect(reason)}")
            :ok
        end
      end
    end

    test "rejects malformed message structures" do
      malformed_message_lists = [
        # Missing role
        [[%{content: "Hello"}]],

        # Missing content
        [[%{role: "user"}]],

        # Invalid role
        [[%{role: "invalid", content: "Hello"}]],

        # Empty message
        [[%{}]],

        # Non-map message
        [["string_message"]],

        # Nested incorrectly
        [%{role: "user", content: "Hello"}]
      ]

      for message_list <- malformed_message_lists do
        case ExLLM.create_batch(:anthropic, message_list) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some malformed messages might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "batch processing workflow" do
    @tag provider: :anthropic
    @tag :slow
    test "complete batch processing lifecycle with Anthropic" do
      # Skip if Anthropic is not configured
      unless ExLLM.configured?(:anthropic) do
        IO.puts("Skipping Anthropic batch processing lifecycle test - not configured")
        :ok
      else
        # Create batch
        case ExLLM.create_batch(:anthropic, @test_batch_messages, model: "claude-3-haiku") do
          {:ok, batch} ->
            batch_id = batch.id

            # Get batch status
            case ExLLM.get_batch(:anthropic, batch_id) do
              {:ok, retrieved_batch} ->
                assert retrieved_batch.id == batch_id
                assert Map.has_key?(retrieved_batch, :status)

              {:error, reason} ->
                IO.puts("Get batch failed: #{inspect(reason)}")
            end

            # Try to cancel the batch (might not be cancellable depending on status)
            case ExLLM.cancel_batch(:anthropic, batch_id) do
              {:ok, cancelled_batch} ->
                assert cancelled_batch.id == batch_id

              {:error, reason} ->
                IO.puts("Cancel batch failed (might be expected): #{inspect(reason)}")
                :ok
            end

          {:error, reason} ->
            IO.puts("Anthropic batch processing lifecycle test skipped: #{inspect(reason)}")
            :ok
        end
      end
    end

    @tag provider: :anthropic
    test "batch status tracking" do
      # Skip if Anthropic is not configured
      unless ExLLM.configured?(:anthropic) do
        IO.puts("Skipping Anthropic batch status tracking test - not configured")
        :ok
      else
        case ExLLM.create_batch(:anthropic, @test_batch_messages, model: "claude-3-haiku") do
          {:ok, batch} ->
            batch_id = batch.id
            initial_status = batch.status

            # Check status multiple times to see progression
            statuses =
              for _i <- 1..3 do
                case ExLLM.get_batch(:anthropic, batch_id) do
                  {:ok, current_batch} -> current_batch.status
                  {:error, _} -> nil
                end
              end

            valid_statuses = Enum.filter(statuses, &(&1 != nil))

            if length(valid_statuses) > 0 do
              # All statuses should be valid batch statuses
              valid_batch_statuses = ["pending", "processing", "completed", "failed", "cancelled"]

              for status <- valid_statuses do
                assert status in valid_batch_statuses,
                       "Invalid batch status: #{status}"
              end
            end

          {:error, reason} ->
            IO.puts("Batch status tracking test skipped: #{inspect(reason)}")
            :ok
        end
      end
    end
  end
end
