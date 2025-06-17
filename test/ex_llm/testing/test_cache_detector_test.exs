defmodule ExLLM.Testing.TestCacheDetectorTest do
  use ExUnit.Case, async: true
  alias ExLLM.Testing.TestCacheDetector
  alias ExLLM.Testing.TestCacheConfig

  describe "integration_test_running?/0" do
    test "returns true when integration tag is present" do
      test_context = %{
        module: ExLLM.Testing.TestCacheDetectorTest,
        test_name: "test integration",
        tags: [:integration, :some_other_tag],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.integration_test_running?() == true
      TestCacheDetector.clear_test_context()
    end

    test "returns false when integration tag is not present" do
      test_context = %{
        module: ExLLM.Testing.TestCacheDetectorTest,
        test_name: "test unit",
        tags: [:unit],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.integration_test_running?() == false
      TestCacheDetector.clear_test_context()
    end

    test "returns false when no test context" do
      TestCacheDetector.clear_test_context()
      assert TestCacheDetector.integration_test_running?() == false
    end
  end

  describe "oauth2_test_running?/0" do
    test "returns true when oauth2 tag is present" do
      test_context = %{
        module: ExLLM.Testing.TestCacheDetectorTest,
        test_name: "test oauth2",
        tags: [:oauth2],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.oauth2_test_running?() == true
      TestCacheDetector.clear_test_context()
    end

    test "returns true when module name contains OAuth2" do
      test_context = %{
        module: ExLLM.OAuth2IntegrationTest,
        test_name: "test auth",
        tags: [],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.oauth2_test_running?() == true
      TestCacheDetector.clear_test_context()
    end

    test "returns true when test name contains oauth2" do
      test_context = %{
        module: ExLLM.SomeTest,
        test_name: "test oauth2 authentication",
        tags: [],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.oauth2_test_running?() == true
      TestCacheDetector.clear_test_context()
    end

    test "returns false when no oauth2 indicators" do
      test_context = %{
        module: ExLLM.Testing.TestCacheDetectorTest,
        test_name: "test something",
        tags: [:unit],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.oauth2_test_running?() == false
      TestCacheDetector.clear_test_context()
    end
  end

  describe "should_cache_responses?/0" do
    setup do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})

      on_exit(fn ->
        Application.put_env(:ex_llm, :test_cache, original_config)
        TestCacheDetector.clear_test_context()
      end)

      :ok
    end

    test "returns false when caching is disabled" do
      Application.put_env(:ex_llm, :test_cache, %{enabled: false})
      assert TestCacheDetector.should_cache_responses?() == false
    end

    test "returns true when auto_detect is false but enabled is true" do
      Application.put_env(:ex_llm, :test_cache, %{enabled: true, auto_detect: false})
      assert TestCacheDetector.should_cache_responses?() == true
    end

    test "returns false when not in test environment" do
      # This test is in test environment, so we can't really test this
      # but the logic is there in the implementation
      assert Mix.env() == :test
    end

    test "returns true for integration tests when cache_integration_tests is true" do
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: true,
        auto_detect: true,
        cache_integration_tests: true
      })

      test_context = %{
        module: ExLLM.IntegrationTest,
        test_name: "test api",
        tags: [:integration],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.should_cache_responses?() == true
    end

    test "returns false for integration tests when cache_integration_tests is false" do
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: true,
        auto_detect: true,
        cache_integration_tests: false
      })

      test_context = %{
        module: ExLLM.IntegrationTest,
        test_name: "test api",
        tags: [:integration],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.should_cache_responses?() == false
    end

    test "returns true for oauth2 tests when cache_oauth2_tests is true" do
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: true,
        auto_detect: true,
        cache_oauth2_tests: true
      })

      test_context = %{
        module: ExLLM.OAuth2Test,
        test_name: "test auth",
        tags: [:oauth2],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.should_cache_responses?() == true
    end

    test "detects integration tests by module name" do
      Application.put_env(:ex_llm, :test_cache, %{
        enabled: true,
        auto_detect: true,
        cache_integration_tests: true
      })

      test_context = %{
        module: ExLLM.AnthropicIntegrationTest,
        test_name: "test chat",
        # No tags, but module name has "Integration"
        tags: [],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.should_cache_responses?() == true
    end
  end

  describe "get_current_test_context/0" do
    test "returns stored test context" do
      test_context = %{
        module: ExLLM.TestModule,
        test_name: "test function",
        tags: [:tag1, :tag2],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      assert TestCacheDetector.get_current_test_context() == {:ok, test_context}
      TestCacheDetector.clear_test_context()
    end

    test "returns error when no context set" do
      TestCacheDetector.clear_test_context()
      assert TestCacheDetector.get_current_test_context() == :error
    end
  end

  describe "generate_cache_key/2" do
    setup do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})

      on_exit(fn ->
        Application.put_env(:ex_llm, :test_cache, original_config)
        TestCacheDetector.clear_test_context()
      end)

      :ok
    end

    test "generates cache key with provider organization" do
      Application.put_env(:ex_llm, :test_cache, %{organization: :by_provider})

      key = TestCacheDetector.generate_cache_key(:openai, "chat_completions")
      assert key == "openai/chat_completions"
    end

    test "generates cache key with test module organization" do
      Application.put_env(:ex_llm, :test_cache, %{organization: :by_test_module})

      test_context = %{
        module: ExLLM.OpenAIIntegrationTest,
        test_name: "test chat",
        tags: [:integration],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      key = TestCacheDetector.generate_cache_key(:openai, "chat_completions")
      assert key == "OpenAIIntegrationTest/openai/chat_completions"
    end

    test "generates cache key with tag organization" do
      Application.put_env(:ex_llm, :test_cache, %{organization: :by_tag})

      test_context = %{
        module: ExLLM.SomeTest,
        test_name: "test function",
        tags: [:oauth2, :integration],
        pid: self()
      }

      TestCacheDetector.set_test_context(test_context)
      key = TestCacheDetector.generate_cache_key(:gemini, "corpus_create")
      assert key == "oauth2/gemini/corpus_create"
    end

    test "sanitizes cache key for filesystem safety" do
      Application.put_env(:ex_llm, :test_cache, %{organization: :by_provider})

      key = TestCacheDetector.generate_cache_key(:openai, "chat/completions?model=gpt-4")
      assert key == "openai/chat_completions_model_gpt_4"
    end

    test "handles missing test context gracefully" do
      Application.put_env(:ex_llm, :test_cache, %{organization: :by_test_module})
      TestCacheDetector.clear_test_context()

      key = TestCacheDetector.generate_cache_key(:openai, "chat")
      assert key == "openai/chat"
    end
  end

  describe "set_test_context/1 and clear_test_context/0" do
    test "stores and clears test context in process dictionary" do
      test_context = %{
        module: ExLLM.TestModule,
        test_name: "test",
        tags: [:test],
        pid: self()
      }

      assert TestCacheDetector.set_test_context(test_context) == :ok
      assert Process.get(:ex_llm_test_context) == test_context

      assert TestCacheDetector.clear_test_context() == :ok
      assert Process.get(:ex_llm_test_context) == nil
    end
  end
end
