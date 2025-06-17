defmodule ExLLM.Gemini.QAIntegrationTest do
  use ExUnit.Case, async: false

  alias ExLLM.Providers.Gemini.QA

  @moduletag :integration
  @moduletag :gemini_qa_integration

  describe "generate_answer/3 with API" do
    @describetag :skip_without_api_key
    setup do
      api_key = System.get_env("GEMINI_API_KEY")

      if is_nil(api_key) do
        {:skip, "GEMINI_API_KEY not set"}
      else
        {:ok, api_key: api_key}
      end
    end

    test "generates answer with inline passages", %{api_key: api_key} do
      contents = [
        %{
          parts: [%{text: "What is the capital of France based on the provided information?"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "france_info",
          content: %{
            parts: [
              %{
                text:
                  "France is a country in Western Europe. Paris is the capital city of France and also its largest city. The city is known for landmarks like the Eiffel Tower and the Louvre Museum."
              }
            ]
          }
        }
      ]

      opts = [
        inline_passages: passages,
        temperature: 0.1,
        api_key: api_key
      ]

      {:ok, response} =
        QA.generate_answer("models/gemini-1.5-flash", contents, :abstractive, opts)

      assert response.answer != nil
      assert response.answer.content.parts != []

      # Check that the answer mentions Paris
      answer_text = response.answer.content.parts |> List.first() |> Map.get(:text, "")
      assert String.contains?(String.downcase(answer_text), "paris")

      # Should have high answerable probability for well-grounded question
      if response.answerable_probability do
        assert response.answerable_probability > 0.5
      end
    end

    test "handles question with insufficient grounding", %{api_key: api_key} do
      contents = [
        %{
          parts: [%{text: "What is the population of Mars colonies in 2024?"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "earth_info",
          content: %{
            parts: [
              %{
                text:
                  "Earth is the third planet from the Sun and has a population of approximately 8 billion people as of 2024."
              }
            ]
          }
        }
      ]

      opts = [
        inline_passages: passages,
        temperature: 0.1,
        api_key: api_key
      ]

      {:ok, response} =
        QA.generate_answer("models/gemini-1.5-flash", contents, :abstractive, opts)

      assert response.answer != nil

      # Should have low answerable probability since the question isn't grounded in the passages
      if response.answerable_probability do
        assert response.answerable_probability < 0.5
      end
    end

    test "handles different answer styles", %{api_key: api_key} do
      contents = [
        %{
          parts: [%{text: "What is machine learning?"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "ml_definition",
          content: %{
            parts: [
              %{
                text:
                  "Machine learning is a subset of artificial intelligence that enables computers to learn and make decisions from data without being explicitly programmed. It involves algorithms that can identify patterns in data and make predictions or classifications based on those patterns."
              }
            ]
          }
        }
      ]

      opts = [
        inline_passages: passages,
        temperature: 0.1,
        api_key: api_key
      ]

      # Test different answer styles
      for style <- [:abstractive, :extractive, :verbose] do
        {:ok, response} = QA.generate_answer("models/gemini-1.5-flash", contents, style, opts)

        assert response.answer != nil
        assert response.answer.content.parts != []

        answer_text = response.answer.content.parts |> List.first() |> Map.get(:text, "")
        assert String.length(answer_text) > 0

        case style do
          :extractive ->
            # Extractive should be brief
            assert String.length(answer_text) < 200

          :verbose ->
            # Verbose should be longer (though this depends on the content)
            assert String.length(answer_text) > 50

          :abstractive ->
            # Abstractive should be somewhere in between
            assert String.length(answer_text) > 20
        end
      end
    end

    test "handles multi-turn conversation", %{api_key: api_key} do
      contents = [
        %{
          parts: [%{text: "Tell me about renewable energy."}],
          role: "user"
        },
        %{
          parts: [
            %{
              text:
                "Renewable energy comes from natural sources that replenish themselves, like solar and wind power."
            }
          ],
          role: "model"
        },
        %{
          parts: [%{text: "What are the main benefits of solar energy specifically?"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "solar_benefits",
          content: %{
            parts: [
              %{
                text:
                  "Solar energy benefits include: 1) It's environmentally clean with no emissions, 2) It reduces electricity bills over time, 3) It's renewable and inexhaustible, 4) It requires minimal maintenance once installed, 5) It can increase property values."
              }
            ]
          }
        }
      ]

      opts = [
        inline_passages: passages,
        temperature: 0.1,
        api_key: api_key
      ]

      {:ok, response} = QA.generate_answer("models/gemini-1.5-flash", contents, :verbose, opts)

      assert response.answer != nil
      assert response.answer.content.parts != []

      answer_text = response.answer.content.parts |> List.first() |> Map.get(:text, "")

      # Should mention some benefits of solar energy
      downcase_answer = String.downcase(answer_text)

      assert String.contains?(downcase_answer, "solar") ||
               String.contains?(downcase_answer, "benefit")
    end

    test "handles safety filtering", %{api_key: api_key} do
      contents = [
        %{
          parts: [%{text: "What is a peaceful resolution?"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "peace_info",
          content: %{
            parts: [
              %{
                text:
                  "Peaceful resolutions involve dialogue, negotiation, and compromise to solve conflicts without violence."
              }
            ]
          }
        }
      ]

      safety_settings = [
        %{
          category: "HARM_CATEGORY_HARASSMENT",
          threshold: "BLOCK_MEDIUM_AND_ABOVE"
        },
        %{
          category: "HARM_CATEGORY_DANGEROUS_CONTENT",
          threshold: "BLOCK_MEDIUM_AND_ABOVE"
        }
      ]

      opts = [
        inline_passages: passages,
        safety_settings: safety_settings,
        temperature: 0.1,
        api_key: api_key
      ]

      {:ok, response} =
        QA.generate_answer("models/gemini-1.5-flash", contents, :abstractive, opts)

      assert response.answer != nil

      # Input feedback should be present with safety ratings
      if response.input_feedback do
        assert is_list(response.input_feedback.safety_ratings)
      end
    end

    test "handles API errors gracefully", %{api_key: _api_key} do
      contents = [
        %{
          parts: [%{text: "Test question"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "test_passage",
          content: %{parts: [%{text: "Test content"}]}
        }
      ]

      # Test with invalid API key
      opts = [
        inline_passages: passages,
        api_key: "invalid_key"
      ]

      {:error, error} =
        QA.generate_answer("models/gemini-1.5-flash", contents, :abstractive, opts)

      assert error.status in [401, 403]
      assert is_binary(error.message)
    end

    test "handles invalid model name", %{api_key: api_key} do
      contents = [
        %{
          parts: [%{text: "Test question"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "test_passage",
          content: %{parts: [%{text: "Test content"}]}
        }
      ]

      opts = [
        inline_passages: passages,
        api_key: api_key
      ]

      {:error, error} =
        QA.generate_answer("models/nonexistent-model", contents, :abstractive, opts)

      assert error.status in [400, 404]
      assert is_binary(error.message)
    end
  end

  describe "generate_answer/3 with semantic retriever" do
    @describetag :skip_without_oauth
    setup do
      oauth_token = System.get_env("GEMINI_OAUTH_TOKEN")
      test_corpus = System.get_env("GEMINI_TEST_CORPUS")

      cond do
        is_nil(oauth_token) ->
          {:skip, "GEMINI_OAUTH_TOKEN not set"}

        is_nil(test_corpus) ->
          {:skip, "GEMINI_TEST_CORPUS not set"}

        true ->
          {:ok, oauth_token: oauth_token, test_corpus: test_corpus}
      end
    end

    test "generates answer using semantic retriever", %{
      oauth_token: oauth_token,
      test_corpus: test_corpus
    } do
      contents = [
        %{
          parts: [%{text: "What is artificial intelligence?"}],
          role: "user"
        }
      ]

      semantic_retriever = %{
        source: test_corpus,
        query: %{parts: [%{text: "artificial intelligence definition"}]},
        max_chunks_count: 3,
        minimum_relevance_score: 0.5
      }

      opts = [
        semantic_retriever: semantic_retriever,
        temperature: 0.2,
        oauth_token: oauth_token
      ]

      {:ok, response} = QA.generate_answer("models/gemini-1.5-flash", contents, :verbose, opts)

      assert response.answer != nil
      assert response.answer.content.parts != []

      answer_text = response.answer.content.parts |> List.first() |> Map.get(:text, "")
      assert String.length(answer_text) > 0

      # Should have grounding metadata since it used semantic retrieval
      if response.answer.grounding_metadata do
        assert is_list(response.answer.grounding_metadata.grounding_chunks)
      end
    end
  end
end
