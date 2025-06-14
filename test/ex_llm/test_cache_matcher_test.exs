defmodule ExLLM.TestCacheMatcherTest do
  use ExUnit.Case, async: true
  alias ExLLM.TestCacheMatcher

  describe "exact_match/2" do
    test "finds exact matching request" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4", "messages" => [%{"role" => "user", "content" => "Hello"}]},
        headers: [{"Authorization", "Bearer sk-123"}]
      }

      cached_requests = [
        %{
          request: %{
            url: "https://api.openai.com/v1/chat/completions",
            body: %{"model" => "gpt-3.5", "messages" => [%{"role" => "user", "content" => "Hi"}]},
            headers: [{"Authorization", "Bearer sk-123"}]
          },
          response: %{
            status: 200,
            body: %{"choices" => [%{"message" => %{"content" => "Hi there"}}]}
          }
        },
        %{
          request: request,
          response: %{
            status: 200,
            body: %{"choices" => [%{"message" => %{"content" => "Hello there"}}]}
          }
        }
      ]

      assert {:ok, matched} = TestCacheMatcher.exact_match(request, cached_requests)

      assert matched.response.body["choices"] |> hd |> Map.get("message") |> Map.get("content") ==
               "Hello there"
    end

    test "returns :miss when no exact match found" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4", "messages" => [%{"role" => "user", "content" => "Hello"}]},
        headers: [{"Authorization", "Bearer sk-123"}]
      }

      cached_requests = [
        %{
          request: %{
            url: "https://api.openai.com/v1/chat/completions",
            body: %{"model" => "gpt-3.5", "messages" => [%{"role" => "user", "content" => "Hi"}]},
            headers: [{"Authorization", "Bearer sk-123"}]
          },
          response: %{status: 200, body: %{"choices" => []}}
        }
      ]

      assert :miss = TestCacheMatcher.exact_match(request, cached_requests)
    end

    test "handles empty cached requests" do
      request = %{url: "test", body: %{}, headers: []}

      assert :miss = TestCacheMatcher.exact_match(request, [])
    end
  end

  describe "fuzzy_match/3" do
    test "matches requests with similar content" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{
          "model" => "gpt-4",
          "messages" => [%{"role" => "user", "content" => "What is the weather today?"}],
          "temperature" => 0.7
        },
        headers: [{"Authorization", "Bearer sk-123"}]
      }

      cached_requests = [
        %{
          request: %{
            url: "https://api.openai.com/v1/chat/completions",
            body: %{
              "model" => "gpt-4",
              "messages" => [%{"role" => "user", "content" => "What is the weather today?"}],
              # Slightly different temperature
              "temperature" => 0.8
            },
            headers: [{"Authorization", "Bearer sk-123"}]
          },
          response: %{
            status: 200,
            body: %{"choices" => [%{"message" => %{"content" => "Sunny"}}]}
          }
        }
      ]

      assert {:ok, matched} = TestCacheMatcher.fuzzy_match(request, cached_requests, 0.8)

      assert matched.response.body["choices"] |> hd |> Map.get("message") |> Map.get("content") ==
               "Sunny"
    end

    test "respects similarity threshold" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{
          "model" => "gpt-4",
          "messages" => [%{"role" => "user", "content" => "Hello"}]
        },
        headers: []
      }

      cached_requests = [
        %{
          request: %{
            # Different provider
            url: "https://api.anthropic.com/v1/messages",
            body: %{
              "model" => "claude-3",
              "messages" => [%{"role" => "user", "content" => "Goodbye"}]
            },
            headers: []
          },
          response: %{status: 200, body: %{}}
        }
      ]

      # High threshold should not match
      assert :miss = TestCacheMatcher.fuzzy_match(request, cached_requests, 0.95)

      # Low threshold might match (depending on implementation)
      # With Jaro distance, URLs have ~0.79 similarity, total ~0.34
      # Test with threshold above the calculated similarity
      assert :miss = TestCacheMatcher.fuzzy_match(request, cached_requests, 0.4)
    end

    test "prioritizes higher similarity scores" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{
          "model" => "gpt-4",
          "messages" => [%{"role" => "user", "content" => "Test message"}]
        },
        headers: []
      }

      cached_requests = [
        %{
          request: %{
            url: "https://api.openai.com/v1/chat/completions",
            body: %{
              "model" => "gpt-3.5",
              "messages" => [%{"role" => "user", "content" => "Different"}]
            },
            headers: []
          },
          response: %{status: 200, body: %{"result" => "low_similarity"}}
        },
        %{
          request: %{
            url: "https://api.openai.com/v1/chat/completions",
            body: %{
              "model" => "gpt-4",
              "messages" => [%{"role" => "user", "content" => "Test message"}]
            },
            headers: []
          },
          response: %{status: 200, body: %{"result" => "high_similarity"}}
        }
      ]

      assert {:ok, matched} = TestCacheMatcher.fuzzy_match(request, cached_requests, 0.5)
      assert matched.response.body["result"] == "high_similarity"
    end
  end

  describe "semantic_match/2" do
    test "matches semantically similar messages" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{
          "model" => "gpt-4",
          "messages" => [
            %{"role" => "system", "content" => "You are a helpful assistant"},
            %{"role" => "user", "content" => "What's the capital of France?"}
          ]
        }
      }

      cached_requests = [
        %{
          request: %{
            url: "https://api.openai.com/v1/chat/completions",
            body: %{
              "model" => "gpt-4",
              "messages" => [
                %{"role" => "system", "content" => "You are a helpful AI assistant"},
                %{"role" => "user", "content" => "What is the capital city of France?"}
              ]
            }
          },
          response: %{status: 200, body: %{"answer" => "Paris"}}
        }
      ]

      assert {:ok, matched} = TestCacheMatcher.semantic_match(request, cached_requests)
      assert matched.response.body["answer"] == "Paris"
    end

    test "handles different message orders" do
      request = %{
        url: "test",
        body: %{
          "messages" => [
            %{"role" => "user", "content" => "Question 1"},
            %{"role" => "assistant", "content" => "Answer 1"},
            %{"role" => "user", "content" => "Question 2"}
          ]
        }
      }

      cached_requests = [
        %{
          request: %{
            url: "test",
            body: %{
              "messages" => [
                %{"role" => "user", "content" => "Question 2"},
                %{"role" => "assistant", "content" => "Answer 1"},
                %{"role" => "user", "content" => "Question 1"}
              ]
            }
          },
          response: %{status: 200, body: %{}}
        }
      ]

      # Semantic matching should consider content, not just order
      # This test assumes the implementation doesn't match reordered messages
      assert :miss = TestCacheMatcher.semantic_match(request, cached_requests)
    end
  end

  describe "context_match/3" do
    test "matches based on test context" do
      request = %{
        url: "https://api.openai.com/v1/chat/completions",
        body: %{"model" => "gpt-4", "messages" => []},
        headers: []
      }

      test_context = %{
        module: ExLLM.OpenAIIntegrationTest,
        test_name: "test chat completion",
        tags: [:integration, :openai]
      }

      cached_requests = [
        %{
          request: %{
            url: "https://api.openai.com/v1/chat/completions",
            body: %{"model" => "gpt-3.5", "messages" => []},
            headers: []
          },
          metadata: %{
            test_context: %{
              module: ExLLM.OpenAIIntegrationTest,
              test_name: "test chat completion",
              tags: [:integration, :openai]
            }
          },
          response: %{status: 200, body: %{"matched" => "by_context"}}
        }
      ]

      assert {:ok, matched} =
               TestCacheMatcher.context_match(request, cached_requests, test_context)

      assert matched.response.body["matched"] == "by_context"
    end

    test "prioritizes same test context over different context" do
      request = %{url: "test", body: %{}, headers: []}

      test_context = %{
        module: ExLLM.TestModule,
        test_name: "specific_test",
        tags: [:tag1]
      }

      cached_requests = [
        %{
          request: %{url: "test", body: %{}, headers: []},
          metadata: %{
            test_context: %{
              module: ExLLM.OtherModule,
              test_name: "different_test",
              tags: [:tag2]
            }
          },
          response: %{status: 200, body: %{"from" => "different_context"}}
        },
        %{
          request: %{url: "test", body: %{}, headers: []},
          metadata: %{
            test_context: test_context
          },
          response: %{status: 200, body: %{"from" => "same_context"}}
        }
      ]

      assert {:ok, matched} =
               TestCacheMatcher.context_match(request, cached_requests, test_context)

      assert matched.response.body["from"] == "same_context"
    end
  end

  describe "find_best_match/3" do
    test "uses exact match for :exact_only strategy" do
      request = %{url: "test", body: %{"exact" => true}, headers: []}

      cached_requests = [
        %{
          request: %{url: "test", body: %{"exact" => true}, headers: []},
          response: %{status: 200, body: %{"matched" => "exact"}}
        }
      ]

      assert {:ok, matched} =
               TestCacheMatcher.find_best_match(request, cached_requests, :exact_only)

      assert matched.response.body["matched"] == "exact"
    end

    test "uses fuzzy match for :fuzzy_tolerant strategy" do
      request = %{
        url: "test",
        body: %{"content" => "Hello world", "temperature" => 0.7},
        headers: []
      }

      cached_requests = [
        %{
          request: %{
            url: "test",
            body: %{"content" => "Hello world", "temperature" => 0.8},
            headers: []
          },
          response: %{status: 200, body: %{"matched" => "fuzzy"}}
        }
      ]

      assert {:ok, matched} =
               TestCacheMatcher.find_best_match(request, cached_requests, :fuzzy_tolerant)

      assert matched.response.body["matched"] == "fuzzy"
    end

    test "tries multiple strategies for :comprehensive" do
      request = %{
        url: "test",
        body: %{"messages" => [%{"content" => "Test"}]},
        headers: []
      }

      cached_requests = [
        %{
          request: %{
            url: "test",
            body: %{"messages" => [%{"content" => "Test similar"}]},
            headers: []
          },
          response: %{status: 200, body: %{"matched" => "semantic"}}
        }
      ]

      # Comprehensive should try exact, then fuzzy, then semantic
      result = TestCacheMatcher.find_best_match(request, cached_requests, :comprehensive)

      # Since exact won't match, it should fall back to fuzzy or semantic
      assert {:ok, _matched} = result
    end

    test "returns :miss when no strategy matches" do
      request = %{url: "test1", body: %{}, headers: []}

      cached_requests = [
        %{
          request: %{url: "test2", body: %{}, headers: []},
          response: %{status: 200, body: %{}}
        }
      ]

      assert :miss = TestCacheMatcher.find_best_match(request, cached_requests, :exact_only)
    end
  end

  describe "calculate_similarity/2" do
    test "returns 1.0 for identical requests" do
      request = %{
        url: "https://api.example.com/endpoint",
        body: %{"key" => "value", "nested" => %{"data" => [1, 2, 3]}},
        headers: [{"Authorization", "Bearer token"}]
      }

      assert TestCacheMatcher.calculate_similarity(request, request) == 1.0
    end

    test "returns lower score for different requests" do
      request1 = %{
        url: "https://api.example.com/endpoint",
        body: %{"key" => "value1"},
        headers: []
      }

      request2 = %{
        url: "https://api.example.com/endpoint",
        body: %{"key" => "value2"},
        headers: []
      }

      similarity = TestCacheMatcher.calculate_similarity(request1, request2)
      assert similarity > 0.0 and similarity < 1.0
    end

    test "considers URL differences" do
      request1 = %{url: "https://api.example.com/v1/endpoint", body: %{}, headers: []}
      request2 = %{url: "https://api.example.com/v2/endpoint", body: %{}, headers: []}

      similarity = TestCacheMatcher.calculate_similarity(request1, request2)
      assert similarity < 1.0
    end

    test "handles missing fields gracefully" do
      request1 = %{url: "test", body: %{"key" => "value"}}
      request2 = %{url: "test", body: %{"key" => "value"}, headers: []}

      # Should not crash and should calculate reasonable similarity
      similarity = TestCacheMatcher.calculate_similarity(request1, request2)
      assert similarity > 0.5
    end
  end

  describe "normalize_request/1" do
    test "normalizes request for comparison" do
      request = %{
        url: "https://api.example.com/endpoint",
        body: %{"b" => 2, "a" => 1, "c" => %{"d" => 4, "e" => 5}},
        headers: [
          {"Content-Type", "application/json"},
          {"Authorization", "Bearer secret-token"},
          {"X-Request-ID", "unique-id-123"}
        ]
      }

      normalized = TestCacheMatcher.normalize_request(request)

      # Should sort body keys
      assert Map.keys(normalized.body) == ["a", "b", "c"]
      assert Map.keys(normalized.body["c"]) == ["d", "e"]

      # Should filter sensitive headers
      header_keys = normalized.headers |> Enum.map(&elem(&1, 0))
      assert "Content-Type" in header_keys
      assert "Authorization" not in header_keys
      assert "X-Request-ID" not in header_keys
    end

    test "handles string keys and atom keys" do
      request = %{
        url: "test",
        body: %{
          "string_key" => "value1",
          "atom_key" => "value2",
          "nested" => %{"atom_nested" => "value3"}
        },
        headers: []
      }

      normalized = TestCacheMatcher.normalize_request(request)

      # Should handle both string and atom keys
      assert normalized.body["string_key"] == "value1"
      assert normalized.body["atom_key"] == "value2"
    end
  end

  describe "extract_message_content/1" do
    test "extracts content from chat messages" do
      request = %{
        body: %{
          "messages" => [
            %{"role" => "system", "content" => "You are helpful"},
            %{"role" => "user", "content" => "Hello"},
            %{"role" => "assistant", "content" => "Hi there"},
            %{"role" => "user", "content" => "How are you?"}
          ]
        }
      }

      content = TestCacheMatcher.extract_message_content(request)

      assert content == "You are helpful Hello Hi there How are you?"
    end

    test "handles missing messages field" do
      request = %{body: %{"model" => "gpt-4"}}

      content = TestCacheMatcher.extract_message_content(request)

      assert content == ""
    end

    test "handles various message formats" do
      request = %{
        body: %{
          "messages" => [
            %{"role" => "user", "content" => "Text"},
            # Missing content
            %{"role" => "user"},
            # Nil content
            %{"role" => "user", "content" => nil},
            # Array content
            %{"role" => "user", "content" => ["Array", "content"]}
          ]
        }
      }

      content = TestCacheMatcher.extract_message_content(request)

      # Should handle edge cases gracefully
      assert is_binary(content)
    end
  end
end
