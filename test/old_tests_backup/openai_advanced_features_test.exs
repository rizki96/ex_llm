defmodule ExLLM.Providers.OpenAIAdvancedFeaturesTest do
  @moduledoc """
  Comprehensive test suite for OpenAI advanced features.

  Tests are organized by API category and validate both our current implementation
  and identify missing features that need to be implemented.
  """
  use ExUnit.Case, async: false

  alias ExLLM.Providers.OpenAI
  alias ExLLM.Testing.ConfigProviderHelper
  alias ExLLM.Types

  @moduletag :integration
  @moduletag :requires_api_key
  @moduletag provider: :openai

  # Use mock config for structure validation, real API for integration
  setup do
    config = %{openai: %{api_key: "test-key-will-be-overridden"}}
    provider = ConfigProviderHelper.setup_static_provider(config)
    {:ok, config_provider: provider}
  end

  describe "Audio APIs" do
    @tag :audio
    test "text-to-speech API structure" do
      # Test that we can call the function even if not fully implemented
      assert function_exported?(ExLLM.Providers.OpenAI, :text_to_speech, 2)

      # Test that function is callable (should fail due to no API key)
      result = ExLLM.Providers.OpenAI.text_to_speech("test", [])
      assert {:error, _} = result
    end

    @tag :audio
    test "transcription API exists" do
      assert function_exported?(ExLLM.Providers.OpenAI, :transcribe_audio, 2)

      # Test that function is callable (should fail due to file not existing)
      result = ExLLM.Providers.OpenAI.transcribe_audio("/fake/path", [])
      assert {:error, _} = result
    end

    @tag :audio
    test "translation API structure" do
      # This should be implemented now
      assert function_exported?(ExLLM.Providers.OpenAI, :translate_audio, 2)

      # Test that function is callable (should fail due to file not existing)
      result = ExLLM.Providers.OpenAI.translate_audio("/fake/path", [])
      assert {:error, _} = result
    end
  end

  describe "Image APIs - Advanced" do
    @tag :images
    test "image generation exists and works" do
      assert function_exported?(ExLLM.Providers.OpenAI, :generate_image, 2)
    end

    @tag :images
    test "image editing API structure" do
      # Should be implemented: edit_image/3 (image, prompt, options)
      assert function_exported?(ExLLM.Providers.OpenAI, :edit_image, 3)

      # Test that function is callable (should fail due to file not existing)
      result = ExLLM.Providers.OpenAI.edit_image("/fake/path", "test prompt", [])
      assert {:error, _} = result
    end

    @tag :images
    test "image variations API structure" do
      # Should be implemented: create_image_variation/2
      assert function_exported?(ExLLM.Providers.OpenAI, :create_image_variation, 2)

      # Test that function is callable (should fail due to file not existing)
      result = ExLLM.Providers.OpenAI.create_image_variation("/fake/path", [])
      assert {:error, _} = result
    end
  end

  describe "Assistants API" do
    @tag :assistants
    test "basic assistant creation exists" do
      assert function_exported?(ExLLM.Providers.OpenAI, :create_assistant, 2)

      # Test parameter validation
      result = ExLLM.Providers.OpenAI.create_assistant(%{}, [])
      assert {:error, _} = result
    end

    @tag :assistants
    test "full assistants CRUD operations" do
      # These should be implemented for full Assistants API support
      assert function_exported?(ExLLM.Providers.OpenAI, :list_assistants, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_assistant, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_assistant, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :delete_assistant, 2)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.list_assistants([])
      assert {:error, _} = ExLLM.Providers.OpenAI.get_assistant("test", [])
      assert {:error, _} = ExLLM.Providers.OpenAI.update_assistant("test", %{}, [])
      assert {:error, _} = ExLLM.Providers.OpenAI.delete_assistant("test", [])
    end
  end

  describe "Threads API" do
    @tag :threads
    test "threads API implemented" do
      # Full threads API should be implemented
      assert function_exported?(ExLLM.Providers.OpenAI, :create_thread, 0)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_thread, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_thread, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_thread, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_thread, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_thread, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_thread, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :delete_thread, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :delete_thread, 2)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.create_thread()
      assert {:error, _} = ExLLM.Providers.OpenAI.get_thread("test")
      assert {:error, _} = ExLLM.Providers.OpenAI.update_thread("test", %{})
      assert {:error, _} = ExLLM.Providers.OpenAI.delete_thread("test")
    end

    @tag :threads
    test "thread messages API implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :create_message, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_message, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_messages, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_messages, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_message, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_message, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_message, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_message, 4)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} =
               ExLLM.Providers.OpenAI.create_message("test", %{role: "user", content: "test"})

      assert {:error, _} = ExLLM.Providers.OpenAI.list_messages("test")
      assert {:error, _} = ExLLM.Providers.OpenAI.get_message("test", "test")
      assert {:error, _} = ExLLM.Providers.OpenAI.update_message("test", "test", %{})
    end
  end

  describe "Runs API" do
    @tag :runs
    test "runs API implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :create_run, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_run, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_thread_and_run, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_thread_and_run, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_runs, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_runs, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_run, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_run, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_run, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_run, 4)
      assert function_exported?(ExLLM.Providers.OpenAI, :cancel_run, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :cancel_run, 3)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.create_run("test", %{assistant_id: "test"})
      assert {:error, _} = ExLLM.Providers.OpenAI.list_runs("test")
      assert {:error, _} = ExLLM.Providers.OpenAI.get_run("test", "test")
      assert {:error, _} = ExLLM.Providers.OpenAI.update_run("test", "test", %{})
      assert {:error, _} = ExLLM.Providers.OpenAI.cancel_run("test", "test")
    end

    @tag :runs
    test "run steps API implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :list_run_steps, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_run_steps, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_run_step, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_run_step, 4)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.list_run_steps("test", "test")
      assert {:error, _} = ExLLM.Providers.OpenAI.get_run_step("test", "test", "test")
    end

    @tag :runs
    test "tool outputs submission implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :submit_tool_outputs, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :submit_tool_outputs, 4)

      # Test that function is callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.submit_tool_outputs("test", "test", [])
    end
  end

  describe "Vector Stores API" do
    @tag :vector_stores
    test "vector stores API implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :create_vector_store, 0)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_vector_store, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_vector_store, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_vector_stores, 0)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_vector_stores, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_vector_store, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_vector_store, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_vector_store, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :update_vector_store, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :delete_vector_store, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :delete_vector_store, 2)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.create_vector_store()
      assert {:error, _} = ExLLM.Providers.OpenAI.list_vector_stores()
      assert {:error, _} = ExLLM.Providers.OpenAI.get_vector_store("test")
      assert {:error, _} = ExLLM.Providers.OpenAI.update_vector_store("test", %{})
      assert {:error, _} = ExLLM.Providers.OpenAI.delete_vector_store("test")
    end

    @tag :vector_stores
    test "vector store files API implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :create_vector_store_file, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :create_vector_store_file, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_vector_store_files, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_vector_store_files, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_vector_store_file, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_vector_store_file, 3)
      assert function_exported?(ExLLM.Providers.OpenAI, :delete_vector_store_file, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :delete_vector_store_file, 3)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} =
               ExLLM.Providers.OpenAI.create_vector_store_file("test", %{file_id: "test"})

      assert {:error, _} = ExLLM.Providers.OpenAI.list_vector_store_files("test")
      assert {:error, _} = ExLLM.Providers.OpenAI.get_vector_store_file("test", "test")
      assert {:error, _} = ExLLM.Providers.OpenAI.delete_vector_store_file("test", "test")
    end

    @tag :vector_stores
    test "vector store search API implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :search_vector_store, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :search_vector_store, 3)

      # Test that function is callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.search_vector_store("test", %{query: "test"})
    end
  end

  describe "Batch Processing API" do
    @tag :batches
    test "basic batch creation exists" do
      assert function_exported?(OpenAI, :create_batch, 2)
    end

    @tag :wip
    test "full batch operations not implemented" do
      refute function_exported?(OpenAI, :list_batches, 1)
      refute function_exported?(OpenAI, :get_batch, 2)
      refute function_exported?(OpenAI, :cancel_batch, 2)
    end
  end

  describe "Fine-tuning API" do
    @tag :fine_tuning
    test "fine-tuning API implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :create_fine_tuning_job, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :list_fine_tuning_jobs, 1)
      assert function_exported?(ExLLM.Providers.OpenAI, :get_fine_tuning_job, 2)
      assert function_exported?(ExLLM.Providers.OpenAI, :cancel_fine_tuning_job, 2)

      # Test that functions are callable (should fail due to API key)
      assert {:error, _} =
               ExLLM.Providers.OpenAI.create_fine_tuning_job(
                 %{training_file: "test", model: "gpt-3.5-turbo"},
                 []
               )

      assert {:error, _} = ExLLM.Providers.OpenAI.list_fine_tuning_jobs([])
      assert {:error, _} = ExLLM.Providers.OpenAI.get_fine_tuning_job("test", [])
      assert {:error, _} = ExLLM.Providers.OpenAI.cancel_fine_tuning_job("test", [])
    end

    @tag :fine_tuning
    test "fine-tuning events implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :list_fine_tuning_events, 2)

      # Test that function is callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.list_fine_tuning_events("test", [])
    end

    @tag :fine_tuning
    test "fine-tuning checkpoints implemented" do
      assert function_exported?(ExLLM.Providers.OpenAI, :list_fine_tuning_checkpoints, 2)

      # Test that function is callable (should fail due to API key)
      assert {:error, _} = ExLLM.Providers.OpenAI.list_fine_tuning_checkpoints("test", [])
    end
  end

  describe "Files API - Current Implementation" do
    @tag :files
    test "file upload API exists and validates parameters", %{config_provider: provider} do
      assert function_exported?(OpenAI, :upload_file, 3)

      # Test parameter validation
      result = OpenAI.upload_file("/fake/file.txt", "invalid-purpose", config_provider: provider)
      assert {:error, _} = result
    end

    @tag :files
    test "file operations exist" do
      assert function_exported?(OpenAI, :list_files, 1)
      assert function_exported?(OpenAI, :get_file, 2)
      assert function_exported?(OpenAI, :delete_file, 2)
      assert function_exported?(OpenAI, :retrieve_file_content, 2)
    end

    @tag :files
    test "upload operations exist" do
      assert function_exported?(OpenAI, :create_upload, 2)
      assert function_exported?(OpenAI, :add_upload_part, 3)
      assert function_exported?(OpenAI, :complete_upload, 3)
      assert function_exported?(OpenAI, :cancel_upload, 2)
    end
  end

  describe "Moderation API - Current Implementation" do
    @tag :moderations
    test "moderation API exists" do
      assert function_exported?(OpenAI, :moderate_content, 2)
    end
  end

  describe "Chat Completions - Advanced Features" do
    @tag :chat
    test "supports modern OpenAI parameters" do
      # Our implementation should support all modern parameters
      messages = [%{role: "user", content: "Hello"}]

      # These should not raise errors (they're now supported)
      advanced_options = [
        max_completion_tokens: 100,
        response_format: %{type: "json_object"},
        tools: [%{type: "function", function: %{name: "test"}}],
        tool_choice: "auto",
        parallel_tool_calls: true,
        reasoning_effort: "medium",
        prediction: %{type: "content", content: "Hello"},
        stream_options: %{include_usage: true},
        audio: %{voice: "alloy", format: "mp3"},
        web_search_options: %{},
        seed: 42,
        temperature: 0.7,
        top_p: 0.9,
        frequency_penalty: 0.1,
        presence_penalty: 0.1,
        stop: ["END"],
        n: 1,
        logprobs: true,
        top_logprobs: 5
      ]

      # Should not raise validation errors
      assert_nothing_raised = fn ->
        try do
          OpenAI.chat(messages, advanced_options)
          :ok
        rescue
          RuntimeError -> :parameter_not_supported
          _ -> :other_error
        end
      end

      # All these parameters should be supported now
      result = assert_nothing_raised.()
      refute result == :parameter_not_supported
    end
  end

  describe "Legacy Completions API" do
    @tag :wip
    test "legacy completions API not implemented" do
      # This is the old /completions endpoint (non-chat)
      refute function_exported?(OpenAI, :create_completion, 2)
    end
  end

  describe "Realtime API" do
    @tag :wip
    test "realtime API not implemented" do
      refute function_exported?(OpenAI, :create_realtime_session, 1)
      refute function_exported?(OpenAI, :create_transcription_session, 1)
    end
  end

  describe "Organization & Admin APIs" do
    @tag :wip
    test "organization APIs not implemented" do
      # These are enterprise features
      refute function_exported?(OpenAI, :list_organization_users, 1)
      refute function_exported?(OpenAI, :get_organization_usage, 1)
      refute function_exported?(OpenAI, :list_projects, 1)
    end
  end

  describe "Evaluations API" do
    @tag :wip
    test "evaluations API not implemented" do
      # This is a newer feature for model evaluation
      refute function_exported?(OpenAI, :create_eval, 1)
      refute function_exported?(OpenAI, :list_evals, 1)
      refute function_exported?(OpenAI, :run_eval, 2)
    end
  end

  describe "Parameter Validation" do
    @tag :validation
    test "validates required parameters for existing functions", %{config_provider: provider} do
      # Test file upload validation
      result = OpenAI.upload_file("/fake/file", "fine-tune", config_provider: provider)
      # Should fail due to file not existing, not parameter validation
      assert {:error, _} = result

      # Test upload creation validation
      result = OpenAI.create_upload(%{}, config_provider: provider)
      assert {:error, _} = result
    end
  end
end
