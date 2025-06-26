defmodule ExLLM.Testing.AdvancedFeatureHelpers do
  @moduledoc """
  Helper utilities for testing advanced ExLLM features.

  Provides reusable patterns and utilities for testing:
  - File management operations
  - Multimodal content (vision/images)
  - API lifecycle patterns
  - Cost-effective testing with caching
  - Mock provider enhancements
  """

  alias ExLLM.TestResponseInterceptor

  @doc """
  Sets up mock responses for file upload operations.

  ## Examples

      setup_mock_file_upload(:openai, "test.pdf", %{id: "file-123", status: "processed"})
  """
  def setup_mock_file_upload(provider, filename, mock_response \\ nil) do
    response =
      mock_response ||
        %{
          id: "file-#{:rand.uniform(10000)}",
          object: "file",
          filename: filename,
          purpose: "assistants",
          status: "processed",
          created_at: System.system_time(:second),
          bytes: 1024
        }

    # Register mock with test interceptor if caching is enabled
    if TestResponseInterceptor.enabled?() do
      TestResponseInterceptor.register_mock(
        {provider, :upload_file, filename},
        {:ok, response}
      )
    end

    response
  end

  @doc """
  Creates a test image fixture for vision testing.

  Returns a base64-encoded 1x1 pixel PNG image by default.

  ## Examples

      image = create_test_image_fixture()
      message = ExLLM.vision_message("What's this?", [image])
  """
  def create_test_image_fixture(opts \\ []) do
    format = Keyword.get(opts, :format, :png)
    size = Keyword.get(opts, :size, {1, 1})

    case format do
      :png ->
        # 1x1 transparent PNG
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

      :jpeg ->
        # 1x1 white JPEG
        "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k="

      :base64 ->
        # Custom base64 data
        Keyword.get(opts, :data, "")
    end
  end

  @doc """
  Creates a test document fixture for knowledge base testing.

  ## Examples

      doc = create_test_document("Test content", title: "Test Doc")
  """
  def create_test_document(content, opts \\ []) do
    %{
      title: Keyword.get(opts, :title, "Test Document"),
      content: content,
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now())
    }
  end

  @doc """
  Asserts a complete API lifecycle (create -> list -> get -> delete).

  This is a reusable pattern for testing CRUD operations on advanced features.

  ## Examples

      assert_api_lifecycle(
        create_fn: fn -> ExLLM.upload_file(:openai, "test.pdf") end,
        list_fn: fn -> ExLLM.list_files(:openai) end,
        get_fn: fn id -> ExLLM.get_file(:openai, id) end,
        delete_fn: fn id -> ExLLM.delete_file(:openai, id) end,
        id_accessor: & &1.id
      )
  """
  def assert_api_lifecycle(opts) do
    create_fn = Keyword.fetch!(opts, :create_fn)
    list_fn = Keyword.fetch!(opts, :list_fn)
    get_fn = Keyword.fetch!(opts, :get_fn)
    delete_fn = Keyword.fetch!(opts, :delete_fn)
    id_accessor = Keyword.get(opts, :id_accessor, & &1.id)

    # Create
    {:ok, created} = create_fn.()
    id = id_accessor.(created)

    # List - verify it exists
    {:ok, items} = list_fn.()
    ids = Enum.map(items, id_accessor)
    assert id in ids, "Created item should appear in list"

    # Get - verify we can retrieve it
    {:ok, retrieved} = get_fn.(id)
    assert id_accessor.(retrieved) == id, "Retrieved item should have same ID"

    # Delete
    :ok = delete_fn.(id)

    # Verify deletion
    {:ok, updated_items} = list_fn.()
    updated_ids = Enum.map(updated_items, id_accessor)
    refute id in updated_ids, "Deleted item should not appear in list"
  end

  @doc """
  Wraps a test with cost-effective caching when available.

  Uses the ExLLM test cache system to avoid repeated API calls.

  ## Examples

      with_test_caching("expensive_vision_test", fn ->
        ExLLM.chat(:openai, messages_with_images)
      end)
  """
  def with_test_caching(test_name, fun) do
    if System.get_env("EX_LLM_TEST_CACHE_ENABLED") == "true" do
      cache_key = "test_cache:#{test_name}"

      case ExLLM.TestCache.get(cache_key) do
        {:ok, cached_result} ->
          cached_result

        :not_found ->
          result = fun.()
          ExLLM.TestCache.put(cache_key, result)
          result
      end
    else
      fun.()
    end
  end

  @doc """
  Sets up a mock provider with enhanced capabilities for complex workflows.

  ## Examples

      setup_enhanced_mock(:openai, %{
        files: true,
        vision: true,
        assistants: true
      })
  """
  def setup_enhanced_mock(provider, capabilities \\ %{}) do
    mock_config = %{
      provider: provider,
      capabilities:
        Map.merge(
          %{
            chat: true,
            streaming: true,
            embeddings: true
          },
          capabilities
        )
    }

    # Configure mock provider responses based on capabilities
    if capabilities[:files] do
      setup_file_management_mocks(provider)
    end

    if capabilities[:vision] do
      setup_vision_mocks(provider)
    end

    if capabilities[:assistants] do
      setup_assistant_mocks(provider)
    end

    mock_config
  end

  @doc """
  Asserts that an API operation returns an expected error.

  ## Examples

      assert_api_error(
        fn -> ExLLM.upload_file(:openai, "invalid.exe") end,
        :invalid_file_type
      )
  """
  def assert_api_error(fun, expected_error_type) do
    case fun.() do
      {:error, %{type: ^expected_error_type}} ->
        :ok

      {:error, %{error: ^expected_error_type}} ->
        :ok

      {:error, ^expected_error_type} ->
        :ok

      result ->
        flunk("Expected error #{inspect(expected_error_type)}, got: #{inspect(result)}")
    end
  end

  @doc """
  Asserts provider-specific error handling.

  ## Examples

      assert_provider_error(:openai, 
        fn -> ExLLM.vision_message("test", [huge_image]) end,
        %{
          openai: :image_too_large,
          anthropic: :content_too_large,
          gemini: :payload_too_large
        }
      )
  """
  def assert_provider_error(provider, fun, expected_errors) do
    expected = Map.get(expected_errors, provider, :generic_error)
    assert_api_error(fun, expected)
  end

  # Private helper functions

  defp setup_file_management_mocks(provider) do
    # Mock file upload response
    ExLLM.Providers.Mock.set_response_handler(fn
      %{endpoint: "/files", method: :post} ->
        %{
          id: "file-#{:rand.uniform(10000)}",
          object: "file",
          status: "processed"
        }

      %{endpoint: "/files", method: :get} ->
        [
          %{id: "file-1", object: "file", filename: "test1.pdf"},
          %{id: "file-2", object: "file", filename: "test2.pdf"}
        ]

      %{endpoint: "/files/" <> file_id, method: :get} ->
        %{id: file_id, object: "file", filename: "test.pdf"}

      %{endpoint: "/files/" <> _file_id, method: :delete} ->
        %{deleted: true}
    end)
  end

  defp setup_vision_mocks(provider) do
    ExLLM.Providers.Mock.set_response_handler(fn
      %{messages: messages} when is_list(messages) ->
        # Check if any message contains image content
        has_images =
          Enum.any?(messages, fn msg ->
            case msg do
              %{content: content} when is_list(content) ->
                Enum.any?(content, &match?(%{type: "image"}, &1))

              _ ->
                false
            end
          end)

        if has_images do
          %{
            content: "I can see the image you provided.",
            model: "gpt-4-vision-preview",
            usage: %{prompt_tokens: 100, completion_tokens: 20}
          }
        else
          %{
            content: "No images found in the message.",
            model: "gpt-4",
            usage: %{prompt_tokens: 50, completion_tokens: 10}
          }
        end
    end)
  end

  defp setup_assistant_mocks(provider) do
    ExLLM.Providers.Mock.set_response_handler(fn
      %{endpoint: "/assistants", method: :post} ->
        %{
          id: "asst_#{:rand.uniform(10000)}",
          object: "assistant",
          created_at: System.system_time(:second),
          name: "Test Assistant"
        }

      %{endpoint: "/threads", method: :post} ->
        %{
          id: "thread_#{:rand.uniform(10000)}",
          object: "thread",
          created_at: System.system_time(:second)
        }

      %{endpoint: "/threads/" <> thread_id <> "/messages", method: :post} ->
        %{
          id: "msg_#{:rand.uniform(10000)}",
          object: "thread.message",
          thread_id: thread_id,
          created_at: System.system_time(:second)
        }

      %{endpoint: "/threads/" <> thread_id <> "/runs", method: :post} ->
        %{
          id: "run_#{:rand.uniform(10000)}",
          object: "thread.run",
          thread_id: thread_id,
          status: "completed",
          created_at: System.system_time(:second)
        }
    end)
  end
end
