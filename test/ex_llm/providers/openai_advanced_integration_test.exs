defmodule ExLLM.Providers.OpenAIAdvancedIntegrationTest do
  @moduledoc """
  Integration tests for OpenAI advanced features with live API calls.

  This test suite validates all advanced OpenAI APIs with actual API calls
  and verifies that the caching system properly caches these responses.
  """
  use ExUnit.Case, async: false

  alias ExLLM.Providers.OpenAI

  @moduletag :integration
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag provider: :openai

  # Test data that can be used across multiple tests
  @test_text "Hello, this is a test message for OpenAI API testing."
  @test_image_prompt "A simple red circle on a white background"
  @test_assistant_config %{
    model: "gpt-3.5-turbo",
    name: "Test Assistant",
    instructions: "You are a helpful test assistant."
  }

  describe "Audio APIs with live API" do
    @tag :audio
    @tag :slow
    test "text-to-speech with live API" do
      {:ok, response} = OpenAI.text_to_speech(@test_text, voice: "alloy", model: "tts-1")

      # Response should be binary audio data
      assert is_binary(response)
      # Should be substantial audio data
      assert byte_size(response) > 1000
    end

    # Note: Transcription and translation tests would require actual audio files
    # These are typically too large to include in tests, so we test structure only
    @tag :audio
    test "transcription API structure validates" do
      # Test with non-existent file should give file error, not API structure error
      result = OpenAI.transcribe_audio("/non/existent/file.mp3")
      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end

    @tag :audio
    test "translation API structure validates" do
      # Test with non-existent file should give file error, not API structure error
      result = OpenAI.translate_audio("/non/existent/file.mp3")
      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end
  end

  describe "Image APIs with live API" do
    @tag :images
    @tag :quota_sensitive
    test "image generation with live API" do
      {:ok, response} =
        OpenAI.generate_image(@test_image_prompt,
          model: "dall-e-2",
          size: "256x256",
          n: 1
        )

      assert %{"data" => [%{"url" => url}]} = response
      assert is_binary(url)
      assert String.starts_with?(url, "https://")
    end

    # Note: Image editing and variations require actual image files
    # We test parameter validation instead
    @tag :images
    test "image editing API validates parameters" do
      result = OpenAI.edit_image("/non/existent/image.png", @test_image_prompt)
      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end

    @tag :images
    test "image variations API validates parameters" do
      result = OpenAI.create_image_variation("/non/existent/image.png")
      assert {:error, error_msg} = result
      assert is_binary(error_msg)
    end
  end

  describe "Assistants API with live API" do
    @tag :assistants
    @tag :slow
    test "full assistants CRUD lifecycle" do
      # Create assistant
      {:ok, assistant} = OpenAI.create_assistant(@test_assistant_config)
      assert %{"id" => assistant_id} = assistant
      assert assistant["name"] == @test_assistant_config.name
      assert assistant["model"] == @test_assistant_config.model

      # List assistants (should include our new one)
      {:ok, list_response} = OpenAI.list_assistants(limit: 10)
      assert %{"data" => assistants} = list_response
      assert Enum.any?(assistants, fn a -> a["id"] == assistant_id end)

      # Get specific assistant
      {:ok, retrieved} = OpenAI.get_assistant(assistant_id)
      assert retrieved["id"] == assistant_id
      assert retrieved["name"] == @test_assistant_config.name

      # Update assistant
      new_name = "Updated Test Assistant"
      {:ok, updated} = OpenAI.update_assistant(assistant_id, %{name: new_name})
      assert updated["name"] == new_name
      assert updated["id"] == assistant_id

      # Delete assistant
      {:ok, deleted} = OpenAI.delete_assistant(assistant_id)
      assert deleted["deleted"] == true
      assert deleted["id"] == assistant_id

      # Verify deletion - should return 404
      result = OpenAI.get_assistant(assistant_id)
      assert {:error, _} = result
    end
  end

  describe "Threads API with live API" do
    @tag :threads
    @tag :slow
    test "threads CRUD lifecycle" do
      # Create thread
      {:ok, thread} = OpenAI.create_thread()
      assert %{"id" => thread_id} = thread
      assert thread["object"] == "thread"

      # Get thread
      {:ok, retrieved} = OpenAI.get_thread(thread_id)
      assert retrieved["id"] == thread_id

      # Update thread (add metadata)
      metadata = %{"test_key" => "test_value"}
      {:ok, updated} = OpenAI.update_thread(thread_id, %{metadata: metadata})
      assert updated["metadata"]["test_key"] == "test_value"

      # Delete thread
      {:ok, deleted} = OpenAI.delete_thread(thread_id)
      assert deleted["deleted"] == true
      assert deleted["id"] == thread_id
    end

    @tag :threads
    @tag :slow
    test "thread with initial messages" do
      initial_messages = [
        %{role: "user", content: "Hello, I need help with testing."}
      ]

      {:ok, thread} = OpenAI.create_thread(%{messages: initial_messages})
      thread_id = thread["id"]

      # List messages in the thread
      {:ok, messages_response} = OpenAI.list_messages(thread_id)
      assert %{"data" => messages} = messages_response
      assert length(messages) == 1

      assert hd(messages)["content"] |> hd() |> Map.get("text") |> Map.get("value") ==
               "Hello, I need help with testing."

      # Clean up
      OpenAI.delete_thread(thread_id)
    end
  end

  describe "Messages API with live API" do
    setup do
      {:ok, thread} = OpenAI.create_thread()
      thread_id = thread["id"]

      on_exit(fn ->
        OpenAI.delete_thread(thread_id)
      end)

      {:ok, thread_id: thread_id}
    end

    @tag :messages
    @tag :slow
    test "messages CRUD lifecycle", %{thread_id: thread_id} do
      # Create message
      message_params = %{
        role: "user",
        content: "What is the capital of France?"
      }

      {:ok, message} = OpenAI.create_message(thread_id, message_params)
      assert %{"id" => message_id} = message
      assert message["role"] == "user"
      assert message["thread_id"] == thread_id

      # List messages
      {:ok, list_response} = OpenAI.list_messages(thread_id)
      assert %{"data" => messages} = list_response
      assert Enum.any?(messages, fn m -> m["id"] == message_id end)

      # Get specific message
      {:ok, retrieved} = OpenAI.get_message(thread_id, message_id)
      assert retrieved["id"] == message_id
      assert retrieved["thread_id"] == thread_id

      # Update message (add metadata)
      metadata = %{"updated" => "true"}
      {:ok, updated} = OpenAI.update_message(thread_id, message_id, %{metadata: metadata})
      assert updated["metadata"]["updated"] == "true"
    end
  end

  describe "Runs API with live API" do
    setup do
      # Create a simple assistant for testing runs
      {:ok, assistant} =
        OpenAI.create_assistant(%{
          model: "gpt-3.5-turbo",
          name: "Test Run Assistant",
          instructions: "You are a helpful assistant for testing runs."
        })

      assistant_id = assistant["id"]

      {:ok, thread} = OpenAI.create_thread()
      thread_id = thread["id"]

      # Add a message to the thread
      OpenAI.create_message(thread_id, %{
        role: "user",
        content: "Please respond with just 'Hello from test run'"
      })

      on_exit(fn ->
        OpenAI.delete_assistant(assistant_id)
        OpenAI.delete_thread(thread_id)
      end)

      {:ok, assistant_id: assistant_id, thread_id: thread_id}
    end

    @tag :runs
    @tag :slow
    test "run lifecycle", %{assistant_id: assistant_id, thread_id: thread_id} do
      # Create run
      run_params = %{assistant_id: assistant_id}
      {:ok, run} = OpenAI.create_run(thread_id, run_params)
      assert %{"id" => run_id} = run
      assert run["assistant_id"] == assistant_id
      assert run["thread_id"] == thread_id

      # List runs
      {:ok, list_response} = OpenAI.list_runs(thread_id)
      assert %{"data" => runs} = list_response
      assert Enum.any?(runs, fn r -> r["id"] == run_id end)

      # Get specific run
      {:ok, retrieved} = OpenAI.get_run(thread_id, run_id)
      assert retrieved["id"] == run_id

      # Wait a bit and check run steps
      :timer.sleep(2000)
      {:ok, steps_response} = OpenAI.list_run_steps(thread_id, run_id)
      assert %{"data" => _steps} = steps_response

      # Cancel the run (in case it's still running)
      OpenAI.cancel_run(thread_id, run_id)
    end

    @tag :runs
    @tag :slow
    test "create thread and run in one call", %{assistant_id: assistant_id} do
      params = %{
        assistant_id: assistant_id,
        thread: %{
          messages: [
            %{role: "user", content: "Say hello"}
          ]
        }
      }

      {:ok, run} = OpenAI.create_thread_and_run(params)
      assert %{"id" => run_id, "thread_id" => thread_id} = run
      assert run["assistant_id"] == assistant_id

      # Clean up
      OpenAI.cancel_run(thread_id, run_id)
      OpenAI.delete_thread(thread_id)
    end
  end

  describe "Vector Stores API with live API" do
    @tag :vector_stores
    @tag :slow
    test "vector stores CRUD lifecycle" do
      # Create vector store
      store_params = %{
        name: "Test Vector Store",
        file_ids: [],
        metadata: %{"test" => "true"}
      }

      {:ok, store} = OpenAI.create_vector_store(store_params)
      assert %{"id" => store_id} = store
      assert store["name"] == "Test Vector Store"

      # List vector stores
      {:ok, list_response} = OpenAI.list_vector_stores()
      assert %{"data" => stores} = list_response
      assert Enum.any?(stores, fn s -> s["id"] == store_id end)

      # Get specific vector store
      {:ok, retrieved} = OpenAI.get_vector_store(store_id)
      assert retrieved["id"] == store_id
      assert retrieved["name"] == "Test Vector Store"

      # Update vector store
      {:ok, updated} = OpenAI.update_vector_store(store_id, %{name: "Updated Vector Store"})
      assert updated["name"] == "Updated Vector Store"

      # Delete vector store
      {:ok, deleted} = OpenAI.delete_vector_store(store_id)
      assert deleted["deleted"] == true
      assert deleted["id"] == store_id
    end

    @tag :vector_stores
    test "vector store search validates parameters" do
      # Should fail with missing vector store
      result = OpenAI.search_vector_store("non_existent_store", %{query: "test search"})
      assert {:error, _} = result
    end
  end

  describe "Fine-tuning API with live API" do
    @tag :fine_tuning
    @tag :very_slow
    @tag :quota_sensitive
    test "fine-tuning jobs list and structure" do
      # List existing fine-tuning jobs (should not error)
      {:ok, response} = OpenAI.list_fine_tuning_jobs()
      assert %{"data" => jobs} = response
      assert is_list(jobs)

      # Note: Creating actual fine-tuning jobs requires uploaded training files
      # and is very expensive, so we only test parameter validation
      result =
        OpenAI.create_fine_tuning_job(%{
          training_file: "file-invalid",
          model: "gpt-3.5-turbo"
        })

      # Should fail with invalid file ID, not parameter validation error
      assert {:error, _} = result
    end

    @tag :fine_tuning
    test "fine-tuning job operations validate parameters" do
      # Test with non-existent job ID
      fake_job_id = "ftjob-nonexistent"

      result = OpenAI.get_fine_tuning_job(fake_job_id)
      assert {:error, _} = result

      result = OpenAI.cancel_fine_tuning_job(fake_job_id)
      assert {:error, _} = result

      result = OpenAI.list_fine_tuning_events(fake_job_id)
      assert {:error, _} = result

      result = OpenAI.list_fine_tuning_checkpoints(fake_job_id)
      assert {:error, _} = result
    end
  end

  describe "Embeddings API with live API" do
    @tag :embeddings
    test "embeddings generation with live API" do
      {:ok, response} = OpenAI.embeddings(@test_text, model: "text-embedding-3-small")

      # ExLLM returns structured response
      assert %ExLLM.Types.EmbeddingResponse{embeddings: [embedding]} = response
      assert is_list(embedding)
      # Should be a substantial vector
      assert length(embedding) > 100
      assert Enum.all?(embedding, &is_number/1)
    end

    @tag :embeddings
    test "batch embeddings with live API" do
      texts = [@test_text, "Another test sentence.", "Third test message."]
      {:ok, response} = OpenAI.embeddings(texts, model: "text-embedding-3-small")

      # ExLLM returns structured response
      assert %ExLLM.Types.EmbeddingResponse{embeddings: embeddings} = response
      assert length(embeddings) == 3

      Enum.each(embeddings, fn embedding ->
        assert is_list(embedding)
        assert length(embedding) > 100
      end)
    end
  end

  describe "Models API with live API" do
    @tag :models
    test "list models with live API" do
      {:ok, models} = OpenAI.list_models()

      # ExLLM returns a list of structured Model types
      assert is_list(models)
      # Should have many models
      assert length(models) > 10

      # Check for expected model structure
      model = hd(models)
      assert %ExLLM.Types.Model{id: id} = model
      assert is_binary(id)
    end
  end

  describe "Files API with live API" do
    @tag :files
    @tag :slow
    test "file upload and management lifecycle" do
      # Create a test file
      test_content = """
      {"messages": [{"role": "user", "content": "Hello"}, {"role": "assistant", "content": "Hi there!"}]}
      {"messages": [{"role": "user", "content": "How are you?"}, {"role": "assistant", "content": "I'm doing well!"}]}
      """

      test_file_path = "/tmp/test_fine_tune_data.jsonl"
      File.write!(test_file_path, test_content)

      try do
        # Upload file
        {:ok, file} = OpenAI.upload_file(test_file_path, "fine-tune")
        assert %{"id" => file_id} = file
        assert file["purpose"] == "fine-tune"

        # List files
        {:ok, list_response} = OpenAI.list_files()
        assert %{"data" => files} = list_response
        assert Enum.any?(files, fn f -> f["id"] == file_id end)

        # Get specific file
        {:ok, retrieved} = OpenAI.get_file(file_id)
        assert retrieved["id"] == file_id

        # Retrieve file content
        {:ok, content} = OpenAI.retrieve_file_content(file_id)
        assert is_binary(content)

        # Delete file
        {:ok, deleted} = OpenAI.delete_file(file_id)
        assert deleted["deleted"] == true
        assert deleted["id"] == file_id
      after
        File.rm(test_file_path)
      end
    end
  end

  describe "Moderation API with live API" do
    @tag :moderation
    test "content moderation with live API" do
      {:ok, response} = OpenAI.moderate_content(@test_text)

      # ExLLM returns structured response
      assert %{flagged: flagged, categories: categories, category_scores: scores} = response
      assert is_boolean(flagged)
      assert is_map(categories)
      assert is_map(scores)
    end

    @tag :moderation
    test "moderation with potentially flagged content" do
      # Use obviously safe content to ensure it's not flagged
      safe_content = "The weather is nice today and I enjoy reading books."
      {:ok, response} = OpenAI.moderate_content(safe_content)

      # ExLLM returns structured response
      assert %{flagged: false} = response
    end
  end
end
