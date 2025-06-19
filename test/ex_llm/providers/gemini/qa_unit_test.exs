defmodule ExLLM.Gemini.QATest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Gemini.QA

  alias ExLLM.Providers.Gemini.QA.{
    GenerateAnswerRequest,
    GenerateAnswerResponse,
    GroundingPassages,
    GroundingPassage,
    SemanticRetrieverConfig,
    InputFeedback
  }

  @moduletag :gemini_qa

  describe "generate_answer/3" do
    test "builds valid request with inline passages" do
      contents = [
        %{
          parts: [%{text: "What is the capital of France?"}],
          role: "user"
        }
      ]

      passages = [
        %{
          id: "passage_1",
          content: %{
            parts: [
              %{text: "France is a country in Europe. Paris is the capital city of France."}
            ]
          }
        }
      ]

      request =
        QA.build_generate_answer_request(contents, :abstractive, %{
          inline_passages: passages,
          temperature: 0.1,
          safety_settings: [
            %{
              category: "HARM_CATEGORY_HARASSMENT",
              threshold: "BLOCK_MEDIUM_AND_ABOVE"
            }
          ]
        })

      assert %GenerateAnswerRequest{} = request
      assert request.contents == contents
      assert request.answer_style == :abstractive
      assert request.temperature == 0.1
      assert %GroundingPassages{} = request.grounding_source
      assert length(request.grounding_source.passages) == 1

      passage = List.first(request.grounding_source.passages)
      assert %GroundingPassage{} = passage
      assert passage.id == "passage_1"

      assert passage.content.parts == [
               %{text: "France is a country in Europe. Paris is the capital city of France."}
             ]
    end

    test "builds valid request with semantic retriever" do
      contents = [
        %{
          parts: [%{text: "What is machine learning?"}],
          role: "user"
        }
      ]

      request =
        QA.build_generate_answer_request(contents, :verbose, %{
          semantic_retriever: %{
            source: "corpora/my_corpus",
            query: %{parts: [%{text: "machine learning definition"}]},
            max_chunks_count: 5,
            minimum_relevance_score: 0.7,
            metadata_filters: [
              %{
                key: "category",
                conditions: [%{string_value: "technology", operation: "EQUAL"}]
              }
            ]
          },
          temperature: 0.3
        })

      assert %GenerateAnswerRequest{} = request
      assert request.contents == contents
      assert request.answer_style == :verbose
      assert request.temperature == 0.3
      assert %SemanticRetrieverConfig{} = request.grounding_source
      assert request.grounding_source.source == "corpora/my_corpus"
      assert request.grounding_source.max_chunks_count == 5
      assert request.grounding_source.minimum_relevance_score == 0.7
      assert length(request.grounding_source.metadata_filters) == 1
    end

    test "validates required fields" do
      # Test missing contents
      assert_raise ArgumentError, ~r/contents is required/, fn ->
        QA.build_generate_answer_request(nil, :abstractive, %{})
      end

      # Test empty contents
      assert_raise ArgumentError, ~r/contents cannot be empty/, fn ->
        QA.build_generate_answer_request([], :abstractive, %{})
      end

      # Test missing answer style
      assert_raise ArgumentError, ~r/answer_style is required/, fn ->
        QA.build_generate_answer_request([%{parts: [%{text: "test"}]}], nil, %{})
      end

      # Test missing grounding source
      assert_raise ArgumentError, ~r/grounding source is required/, fn ->
        QA.build_generate_answer_request([%{parts: [%{text: "test"}]}], :abstractive, %{})
      end
    end

    test "validates answer style enum" do
      contents = [%{parts: [%{text: "test"}], role: "user"}]
      passages = [%{id: "1", content: %{parts: [%{text: "test"}]}}]

      # Valid styles
      for style <- [:abstractive, :extractive, :verbose] do
        request = QA.build_generate_answer_request(contents, style, %{inline_passages: passages})
        assert request.answer_style == style
      end

      # Invalid style
      assert_raise ArgumentError, ~r/Invalid answer_style/, fn ->
        QA.build_generate_answer_request(contents, :invalid_style, %{inline_passages: passages})
      end
    end

    test "validates temperature range" do
      contents = [%{parts: [%{text: "test"}], role: "user"}]
      passages = [%{id: "1", content: %{parts: [%{text: "test"}]}}]

      # Valid temperatures
      for temp <- [0.0, 0.5, 1.0] do
        request =
          QA.build_generate_answer_request(contents, :abstractive, %{
            inline_passages: passages,
            temperature: temp
          })

        assert request.temperature == temp
      end

      # Invalid temperatures
      for temp <- [-0.1, 1.1, 2.0] do
        assert_raise ArgumentError, ~r/Temperature must be between 0.0 and 1.0/, fn ->
          QA.build_generate_answer_request(contents, :abstractive, %{
            inline_passages: passages,
            temperature: temp
          })
        end
      end
    end

    test "validates inline passages structure" do
      contents = [%{parts: [%{text: "test"}], role: "user"}]

      # Valid passages
      passages = [
        %{
          id: "passage_1",
          content: %{
            parts: [%{text: "Valid passage content"}]
          }
        }
      ]

      request =
        QA.build_generate_answer_request(contents, :abstractive, %{inline_passages: passages})

      assert %GroundingPassages{} = request.grounding_source

      # Missing passage ID
      invalid_passages = [
        %{
          content: %{parts: [%{text: "Missing ID"}]}
        }
      ]

      assert_raise ArgumentError, ~r/passage id is required/, fn ->
        QA.build_generate_answer_request(contents, :abstractive, %{
          inline_passages: invalid_passages
        })
      end

      # Missing passage content
      invalid_passages = [
        %{
          id: "passage_1"
        }
      ]

      assert_raise ArgumentError, ~r/passage content is required/, fn ->
        QA.build_generate_answer_request(contents, :abstractive, %{
          inline_passages: invalid_passages
        })
      end
    end

    test "validates semantic retriever config" do
      contents = [%{parts: [%{text: "test"}], role: "user"}]

      # Valid semantic retriever
      semantic_retriever = %{
        source: "corpora/test_corpus",
        query: %{parts: [%{text: "test query"}]}
      }

      request =
        QA.build_generate_answer_request(contents, :abstractive, %{
          semantic_retriever: semantic_retriever
        })

      assert %SemanticRetrieverConfig{} = request.grounding_source

      # Missing source
      invalid_retriever = %{
        query: %{parts: [%{text: "test query"}]}
      }

      assert_raise ArgumentError, ~r/semantic retriever source is required/, fn ->
        QA.build_generate_answer_request(contents, :abstractive, %{
          semantic_retriever: invalid_retriever
        })
      end

      # Missing query
      invalid_retriever = %{
        source: "corpora/test_corpus"
      }

      assert_raise ArgumentError, ~r/semantic retriever query is required/, fn ->
        QA.build_generate_answer_request(contents, :abstractive, %{
          semantic_retriever: invalid_retriever
        })
      end
    end
  end

  describe "parse_generate_answer_response/1" do
    test "parses successful response with grounded answer" do
      response_body = %{
        "answer" => %{
          "content" => %{
            "parts" => [%{"text" => "Paris is the capital of France."}],
            "role" => "model"
          },
          "finishReason" => "STOP",
          "index" => 0,
          "safetyRatings" => [
            %{
              "category" => "HARM_CATEGORY_HARASSMENT",
              "probability" => "NEGLIGIBLE"
            }
          ],
          "groundingMetadata" => %{
            "groundingChunks" => [
              %{
                "chunkId" => "passage_1",
                "web" => %{
                  "uri" => "https://example.com",
                  "title" => "France Information"
                }
              }
            ],
            "groundingSupports" => [
              %{
                "segment" => %{
                  "startIndex" => 0,
                  "endIndex" => 32,
                  "text" => "Paris is the capital of France."
                },
                "groundingChunkIndices" => [0],
                "confidenceScores" => [0.95]
              }
            ]
          }
        },
        "answerableProbability" => 0.92,
        "inputFeedback" => %{
          "safetyRatings" => [
            %{
              "category" => "HARM_CATEGORY_HARASSMENT",
              "probability" => "NEGLIGIBLE"
            }
          ]
        }
      }

      result = QA.parse_generate_answer_response(response_body)

      assert %GenerateAnswerResponse{} = result
      assert result.answerable_probability == 0.92
      assert result.answer["content"]["parts"] == [%{"text" => "Paris is the capital of France."}]
      assert result.answer["finishReason"] == "STOP"
      assert result.answer["groundingMetadata"] != nil
      assert %InputFeedback{} = result.input_feedback
      assert length(result.input_feedback.safety_ratings) == 1
    end

    test "parses response with low answerable probability" do
      response_body = %{
        "answer" => %{
          "content" => %{
            "parts" => [%{"text" => "I don't have enough information to answer that question."}],
            "role" => "model"
          },
          "finishReason" => "STOP",
          "index" => 0
        },
        "answerableProbability" => 0.23,
        "inputFeedback" => %{
          "safetyRatings" => []
        }
      }

      result = QA.parse_generate_answer_response(response_body)

      assert %GenerateAnswerResponse{} = result
      assert result.answerable_probability == 0.23

      assert result.answer["content"]["parts"] == [
               %{"text" => "I don't have enough information to answer that question."}
             ]
    end

    test "parses response with blocked input" do
      response_body = %{
        "inputFeedback" => %{
          "blockReason" => "SAFETY",
          "safetyRatings" => [
            %{
              "category" => "HARM_CATEGORY_HARASSMENT",
              "probability" => "HIGH"
            }
          ]
        }
      }

      result = QA.parse_generate_answer_response(response_body)

      assert %GenerateAnswerResponse{} = result
      assert result.answer == nil
      assert result.input_feedback.block_reason == :safety
      assert length(result.input_feedback.safety_ratings) == 1
    end

    test "handles missing optional fields" do
      minimal_response = %{
        "answer" => %{
          "content" => %{
            "parts" => [%{"text" => "Simple answer"}],
            "role" => "model"
          },
          "finishReason" => "STOP",
          "index" => 0
        }
      }

      result = QA.parse_generate_answer_response(minimal_response)

      assert %GenerateAnswerResponse{} = result
      assert result.answer["content"]["parts"] == [%{"text" => "Simple answer"}]
      assert result.answerable_probability == nil
      assert result.input_feedback == nil
    end
  end

  describe "format_answer_style/1" do
    test "formats answer style atoms to API strings" do
      assert QA.format_answer_style(:abstractive) == "ABSTRACTIVE"
      assert QA.format_answer_style(:extractive) == "EXTRACTIVE"
      assert QA.format_answer_style(:verbose) == "VERBOSE"
    end

    test "raises error for invalid answer style" do
      assert_raise ArgumentError, ~r/Invalid answer_style/, fn ->
        QA.format_answer_style(:invalid)
      end
    end
  end

  describe "format_block_reason/1" do
    test "formats block reason strings to atoms" do
      assert QA.format_block_reason("SAFETY") == :safety
      assert QA.format_block_reason("OTHER") == :other
      assert QA.format_block_reason("BLOCK_REASON_UNSPECIFIED") == :unspecified
    end

    test "handles unknown block reasons" do
      assert QA.format_block_reason("UNKNOWN_REASON") == :unknown
    end
  end
end
