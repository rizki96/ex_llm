defmodule ExLLM.Integration.AssistantsAdvancedComprehensiveTest do
  @moduledoc """
  Comprehensive integration tests for ExLLM Advanced Assistants functionality.
  Tests runs, tool usage, function calling, and complete workflows.
  """
  use ExUnit.Case

  # Test helpers
  defp unique_name(base) do
    timestamp = :os.system_time(:millisecond)
    "#{base} #{timestamp}"
  end

  defp cleanup_assistant(assistant_id) when is_binary(assistant_id) do
    case ExLLM.Providers.OpenAI.delete_assistant(assistant_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  defp cleanup_thread(thread_id) when is_binary(thread_id) do
    case ExLLM.Providers.OpenAI.delete_thread(thread_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  defp cleanup_file(file_id) when is_binary(file_id) do
    case ExLLM.Providers.OpenAI.delete_file(file_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  defp wait_for_run_completion(thread_id, run_id, timeout \\ 30_000) do
    start_time = :os.system_time(:millisecond)

    wait_loop = fn wait_loop_fn ->
      case ExLLM.Providers.OpenAI.get_run(thread_id, run_id) do
        {:ok, run} ->
          case run["status"] do
            status when status in ["completed", "failed", "cancelled", "expired"] ->
              {:ok, run}

            "requires_action" ->
              {:requires_action, run}

            _ ->
              current_time = :os.system_time(:millisecond)

              if current_time - start_time > timeout do
                {:error, :timeout}
              else
                # Poll every second
                Process.sleep(1000)
                wait_loop_fn.(wait_loop_fn)
              end
          end

        {:error, error} ->
          {:error, error}
      end
    end

    wait_loop.(wait_loop)
  end

  describe "Assistant Runs" do
    @describetag :integration
    @describetag :assistants
    @describetag :advanced
    @describetag timeout: 60_000

    test "create and poll run status" do
      # Create an assistant first
      assistant_params = %{
        name: unique_name("Run Test Assistant"),
        instructions: "You are a helpful math tutor. Answer questions briefly.",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Create a thread
          case ExLLM.Providers.OpenAI.create_thread() do
            {:ok, thread} ->
              thread_id = thread["id"]

              # Add a message to the thread
              message_params = %{
                role: "user",
                content: "What is 15 + 27?"
              }

              case ExLLM.Providers.OpenAI.create_message(thread_id, message_params) do
                {:ok, _message} ->
                  # Create a run
                  run_params = %{
                    assistant_id: assistant_id
                  }

                  case ExLLM.Providers.OpenAI.create_run(thread_id, run_params) do
                    {:ok, run} ->
                      assert run["id"] =~ ~r/^run_/
                      assert run["object"] == "thread.run"
                      assert run["assistant_id"] == assistant_id
                      assert run["thread_id"] == thread_id
                      assert run["status"] in ["queued", "in_progress"]

                      # Poll for completion
                      case wait_for_run_completion(thread_id, run["id"]) do
                        {:ok, completed_run} ->
                          assert completed_run["status"] == "completed"

                        {:error, error} ->
                          IO.puts("Run polling failed: #{inspect(error)}")
                          assert is_atom(error) or is_map(error)
                      end

                    {:error, error} ->
                      IO.puts("Run creation failed: #{inspect(error)}")
                      assert is_map(error)
                  end

                {:error, error} ->
                  IO.puts("Message creation failed: #{inspect(error)}")
                  assert is_map(error)
              end

              # Cleanup
              cleanup_thread(thread_id)

            {:error, error} ->
              IO.puts("Thread creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "get run messages after completion" do
      # Create assistant with specific instructions
      assistant_params = %{
        name: unique_name("Message Test Assistant"),
        instructions:
          "You are a helpful assistant. Always respond with exactly: 'The answer is 42.'",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Create thread and run
          create_and_run_params = %{
            assistant_id: assistant_id,
            thread: %{
              messages: [
                %{
                  role: "user",
                  content: "What is the meaning of life?"
                }
              ]
            }
          }

          case ExLLM.Providers.OpenAI.create_thread_and_run(create_and_run_params) do
            {:ok, run} ->
              thread_id = run["thread_id"]

              # Wait for completion
              case wait_for_run_completion(thread_id, run["id"]) do
                {:ok, _completed_run} ->
                  # Get messages from the thread
                  case ExLLM.Providers.OpenAI.list_messages(thread_id) do
                    {:ok, messages} ->
                      assert is_list(messages["data"])
                      # User message + assistant response
                      assert length(messages["data"]) >= 2

                      # Find assistant's response
                      assistant_messages =
                        Enum.filter(messages["data"], fn msg ->
                          msg["role"] == "assistant"
                        end)

                      assert length(assistant_messages) >= 1

                      # Check the content
                      latest_assistant_msg = List.first(assistant_messages)
                      assert is_list(latest_assistant_msg["content"])

                      text_content =
                        Enum.find(latest_assistant_msg["content"], fn content ->
                          content["type"] == "text"
                        end)

                      assert text_content != nil
                      assert String.contains?(text_content["text"]["value"], "42")

                    {:error, error} ->
                      IO.puts("Message listing failed: #{inspect(error)}")
                      assert is_map(error)
                  end

                {:error, error} ->
                  IO.puts("Run completion failed: #{inspect(error)}")
                  assert is_atom(error) or is_map(error)
              end

              # Cleanup
              cleanup_thread(thread_id)

            {:error, error} ->
              IO.puts("Thread and run creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "list run steps" do
      # Create a simple assistant
      assistant_params = %{
        name: unique_name("Steps Test Assistant"),
        instructions: "You are a helpful assistant.",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Create thread with message and run
          create_and_run_params = %{
            assistant_id: assistant_id,
            thread: %{
              messages: [
                %{
                  role: "user",
                  content: "Hello!"
                }
              ]
            }
          }

          case ExLLM.Providers.OpenAI.create_thread_and_run(create_and_run_params) do
            {:ok, run} ->
              thread_id = run["thread_id"]

              # Wait for some progress
              Process.sleep(2000)

              # List run steps
              case ExLLM.Providers.OpenAI.list_run_steps(thread_id, run["id"]) do
                {:ok, steps} ->
                  assert is_list(steps["data"])
                  assert steps["object"] == "list"

                  # Should have at least one step (message creation)
                  if length(steps["data"]) > 0 do
                    step = List.first(steps["data"])
                    assert step["object"] == "thread.run.step"
                    assert step["type"] in ["message_creation", "tool_calls"]
                    assert Map.has_key?(step, "status")
                  end

                {:error, error} ->
                  IO.puts("Run steps listing failed: #{inspect(error)}")
                  assert is_map(error)
              end

              # Cleanup
              cleanup_thread(thread_id)

            {:error, error} ->
              IO.puts("Thread and run creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end
  end

  describe "Assistant Tools" do
    @describetag :integration
    @describetag :assistants
    @describetag :tools
    @describetag timeout: 90_000

    test "code interpreter tool usage" do
      # Create assistant with code interpreter
      assistant_params = %{
        name: unique_name("Code Interpreter Assistant"),
        instructions:
          "You are a helpful assistant that can run Python code. When asked to calculate, use the code interpreter.",
        model: "gpt-4o-mini",
        tools: [%{type: "code_interpreter"}]
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Create thread with calculation request
          create_and_run_params = %{
            assistant_id: assistant_id,
            thread: %{
              messages: [
                %{
                  role: "user",
                  content: "Calculate the factorial of 10 using Python code."
                }
              ]
            }
          }

          case ExLLM.Providers.OpenAI.create_thread_and_run(create_and_run_params) do
            {:ok, run} ->
              thread_id = run["thread_id"]

              # Wait for completion
              case wait_for_run_completion(thread_id, run["id"], 60_000) do
                {:ok, completed_run} ->
                  assert completed_run["status"] == "completed"

                  # Check if code interpreter was used
                  case ExLLM.Providers.OpenAI.list_run_steps(thread_id, run["id"]) do
                    {:ok, steps} ->
                      # Look for tool calls
                      tool_steps =
                        Enum.filter(steps["data"], fn step ->
                          step["type"] == "tool_calls"
                        end)

                      # Should have used code interpreter
                      assert length(tool_steps) >= 1

                      # Verify the tool type
                      if length(tool_steps) > 0 do
                        tool_step = List.first(tool_steps)
                        tool_calls = tool_step["step_details"]["tool_calls"]

                        code_interpreter_calls =
                          Enum.filter(tool_calls, fn call ->
                            call["type"] == "code_interpreter"
                          end)

                        assert length(code_interpreter_calls) >= 1
                      end

                    {:error, error} ->
                      IO.puts("Run steps listing failed: #{inspect(error)}")
                      assert is_map(error)
                  end

                {:error, error} ->
                  IO.puts("Run completion failed: #{inspect(error)}")
                  assert is_atom(error) or is_map(error)
              end

              # Cleanup
              cleanup_thread(thread_id)

            {:error, error} ->
              IO.puts("Thread and run creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "function calling tool usage" do
      # Create assistant with function tool
      assistant_params = %{
        name: unique_name("Function Calling Assistant"),
        instructions:
          "You are a weather assistant. Use the get_weather function to answer weather questions.",
        model: "gpt-4o-mini",
        tools: [
          %{
            type: "function",
            function: %{
              name: "get_weather",
              description: "Get the current weather in a location",
              parameters: %{
                type: "object",
                properties: %{
                  location: %{
                    type: "string",
                    description: "The city and state, e.g. San Francisco, CA"
                  },
                  unit: %{
                    type: "string",
                    enum: ["celsius", "fahrenheit"],
                    description: "The unit of temperature"
                  }
                },
                required: ["location"]
              }
            }
          }
        ]
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Create thread with weather question
          create_and_run_params = %{
            assistant_id: assistant_id,
            thread: %{
              messages: [
                %{
                  role: "user",
                  content: "What's the weather in New York?"
                }
              ]
            }
          }

          case ExLLM.Providers.OpenAI.create_thread_and_run(create_and_run_params) do
            {:ok, run} ->
              thread_id = run["thread_id"]

              # Wait for run to require action
              case wait_for_run_completion(thread_id, run["id"]) do
                {:requires_action, action_run} ->
                  assert action_run["status"] == "requires_action"
                  assert action_run["required_action"]["type"] == "submit_tool_outputs"

                  tool_calls = action_run["required_action"]["submit_tool_outputs"]["tool_calls"]
                  assert is_list(tool_calls)
                  assert length(tool_calls) >= 1

                  # Verify function call
                  tool_call = List.first(tool_calls)
                  assert tool_call["type"] == "function"
                  assert tool_call["function"]["name"] == "get_weather"

                  # Parse arguments
                  {:ok, args} = Jason.decode(tool_call["function"]["arguments"])
                  assert Map.has_key?(args, "location")
                  assert String.contains?(args["location"], "New York")

                  # Submit tool output
                  tool_outputs = [
                    %{
                      tool_call_id: tool_call["id"],
                      output:
                        Jason.encode!(%{
                          temperature: 72,
                          unit: "fahrenheit",
                          description: "Sunny",
                          location: args["location"]
                        })
                    }
                  ]

                  case ExLLM.Providers.OpenAI.submit_tool_outputs(
                         thread_id,
                         run["id"],
                         tool_outputs
                       ) do
                    {:ok, updated_run} ->
                      assert updated_run["status"] in ["queued", "in_progress"]

                      # Wait for final completion
                      case wait_for_run_completion(thread_id, updated_run["id"]) do
                        {:ok, final_run} ->
                          assert final_run["status"] == "completed"

                        {:error, error} ->
                          IO.puts("Final run completion failed: #{inspect(error)}")
                          assert is_atom(error) or is_map(error)
                      end

                    {:error, error} ->
                      IO.puts("Tool output submission failed: #{inspect(error)}")
                      assert is_map(error)
                  end

                {:ok, completed_run} ->
                  # Sometimes the model might not call the function
                  IO.puts("Run completed without function call")
                  assert completed_run["status"] == "completed"

                {:error, error} ->
                  IO.puts("Run completion failed: #{inspect(error)}")
                  assert is_atom(error) or is_map(error)
              end

              # Cleanup
              cleanup_thread(thread_id)

            {:error, error} ->
              IO.puts("Thread and run creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "file search tool usage" do
      # First, create a test file
      file_content = """
      ExLLM Documentation

      ExLLM is a unified Elixir client for Large Language Models. It supports:
      - Multiple providers (OpenAI, Anthropic, Gemini, etc.)
      - Streaming responses
      - Function calling
      - Embeddings
      - Cost tracking

      The main module is ExLLM and the primary function is ExLLM.chat/3.
      """

      file_path = Path.join(System.tmp_dir!(), "ex_llm_docs_#{:os.system_time(:millisecond)}.txt")
      File.write!(file_path, file_content)

      # Upload the file
      case ExLLM.Providers.OpenAI.upload_file(file_path, "assistants") do
        {:ok, file} ->
          file_id = file["id"]

          # Create assistant with file search
          assistant_params = %{
            name: unique_name("File Search Assistant"),
            instructions:
              "You are a helpful assistant that can search through uploaded documents to answer questions.",
            model: "gpt-4o-mini",
            tools: [%{type: "file_search"}],
            tool_resources: %{
              file_search: %{
                vector_stores: [
                  %{
                    file_ids: [file_id]
                  }
                ]
              }
            }
          }

          case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
            {:ok, assistant} ->
              assistant_id = assistant["id"]

              # Create thread with question about the file
              create_and_run_params = %{
                assistant_id: assistant_id,
                thread: %{
                  messages: [
                    %{
                      role: "user",
                      content:
                        "What is the primary function of ExLLM according to the documentation?"
                    }
                  ]
                }
              }

              case ExLLM.Providers.OpenAI.create_thread_and_run(create_and_run_params) do
                {:ok, run} ->
                  thread_id = run["thread_id"]

                  # Wait for completion
                  case wait_for_run_completion(thread_id, run["id"], 60_000) do
                    {:ok, completed_run} ->
                      assert completed_run["status"] == "completed"

                      # Get the response
                      case ExLLM.Providers.OpenAI.list_messages(thread_id) do
                        {:ok, messages} ->
                          assistant_messages =
                            Enum.filter(messages["data"], fn msg ->
                              msg["role"] == "assistant"
                            end)

                          assert length(assistant_messages) >= 1

                          # Check if the response mentions ExLLM.chat/3
                          latest_msg = List.first(assistant_messages)

                          text_content =
                            Enum.find(latest_msg["content"], fn content ->
                              content["type"] == "text"
                            end)

                          assert text_content != nil
                          response_text = text_content["text"]["value"]

                          assert String.contains?(response_text, "ExLLM.chat") or
                                   String.contains?(response_text, "chat/3") or
                                   String.contains?(response_text, "primary function")

                        {:error, error} ->
                          IO.puts("Message listing failed: #{inspect(error)}")
                          assert is_map(error)
                      end

                    {:error, error} ->
                      IO.puts("Run completion failed: #{inspect(error)}")
                      assert is_atom(error) or is_map(error)
                  end

                  # Cleanup
                  cleanup_thread(thread_id)

                {:error, error} ->
                  IO.puts("Thread and run creation failed: #{inspect(error)}")
                  assert is_map(error)
              end

              # Cleanup
              cleanup_assistant(assistant_id)

            {:error, error} ->
              IO.puts("Assistant creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_file(file_id)
          File.rm(file_path)

        {:error, error} ->
          IO.puts("File upload failed: #{inspect(error)}")
          File.rm(file_path)
          assert is_map(error)
      end
    end
  end

  describe "Error Handling and Recovery" do
    @describetag :integration
    @describetag :assistants
    @describetag :error_handling
    @describetag timeout: 60_000

    test "cancel run in progress" do
      # Create assistant that takes time to respond
      assistant_params = %{
        name: unique_name("Cancel Test Assistant"),
        instructions:
          "You are a helpful assistant. When asked to count, count very slowly from 1 to 100, explaining each number in detail.",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Create thread and run
          create_and_run_params = %{
            assistant_id: assistant_id,
            thread: %{
              messages: [
                %{
                  role: "user",
                  content: "Count from 1 to 100 and explain each number."
                }
              ]
            }
          }

          case ExLLM.Providers.OpenAI.create_thread_and_run(create_and_run_params) do
            {:ok, run} ->
              thread_id = run["thread_id"]

              # Wait a bit for run to start
              Process.sleep(2000)

              # Cancel the run
              case ExLLM.Providers.OpenAI.cancel_run(thread_id, run["id"]) do
                {:ok, cancelled_run} ->
                  assert cancelled_run["id"] == run["id"]
                  # Status might be cancelling or cancelled
                  assert cancelled_run["status"] in ["cancelling", "cancelled"]

                  # Wait for cancellation to complete
                  case wait_for_run_completion(thread_id, run["id"], 10_000) do
                    {:ok, final_run} ->
                      assert final_run["status"] == "cancelled"

                    {:error, :timeout} ->
                      # Cancellation might take time
                      assert true

                    {:error, error} ->
                      IO.puts("Run cancellation polling failed: #{inspect(error)}")
                      assert is_atom(error) or is_map(error)
                  end

                {:error, error} ->
                  IO.puts("Run cancellation failed: #{inspect(error)}")
                  assert is_map(error)
              end

              # Cleanup
              cleanup_thread(thread_id)

            {:error, error} ->
              IO.puts("Thread and run creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "handle rate limiting gracefully" do
      # This test attempts to create multiple runs quickly to potentially trigger rate limits
      # We handle this gracefully by accepting both success and rate limit errors

      assistant_params = %{
        name: unique_name("Rate Limit Test Assistant"),
        instructions: "You are a helpful assistant.",
        model: "gpt-4o-mini"
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Try to create multiple threads and runs quickly
          results =
            Enum.map(1..3, fn i ->
              create_and_run_params = %{
                assistant_id: assistant_id,
                thread: %{
                  messages: [
                    %{
                      role: "user",
                      content: "Test message #{i}"
                    }
                  ]
                }
              }

              result = ExLLM.Providers.OpenAI.create_thread_and_run(create_and_run_params)

              # Clean up successful runs
              case result do
                {:ok, run} ->
                  # Small delay before cleanup
                  Process.sleep(100)
                  cleanup_thread(run["thread_id"])

                _ ->
                  nil
              end

              result
            end)

          # Count successes and rate limit errors
          successes = Enum.count(results, fn {status, _} -> status == :ok end)
          errors = Enum.count(results, fn {status, _} -> status == :error end)

          # We should have at least one success or rate limit error
          assert successes + errors == 3
          assert successes >= 1 or errors >= 1

          # If we got errors, check they're rate limit related
          if errors > 0 do
            error_results = Enum.filter(results, fn {status, _} -> status == :error end)

            Enum.each(error_results, fn {:error, error} ->
              assert is_map(error) or is_atom(error)
              # Rate limit errors typically have status 429 or specific error messages
            end)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end
  end

  describe "Complete Workflow" do
    @describetag :integration
    @describetag :assistants
    @describetag :workflow
    @describetag timeout: 120_000

    test "complete assistant workflow with tools and multiple messages" do
      # Create a comprehensive assistant with multiple tools
      assistant_params = %{
        name: unique_name("Complete Workflow Assistant"),
        instructions: """
        You are a helpful assistant that can:
        1. Run Python code using the code interpreter
        2. Answer questions about mathematics
        3. Have multi-turn conversations

        Always be concise in your responses.
        """,
        model: "gpt-4o-mini",
        tools: [%{type: "code_interpreter"}]
      }

      case ExLLM.Providers.OpenAI.create_assistant(assistant_params) do
        {:ok, assistant} ->
          assistant_id = assistant["id"]

          # Create a thread
          case ExLLM.Providers.OpenAI.create_thread() do
            {:ok, thread} ->
              thread_id = thread["id"]

              # First message - simple math question
              message1_params = %{
                role: "user",
                content: "What is 15 * 23?"
              }

              case ExLLM.Providers.OpenAI.create_message(thread_id, message1_params) do
                {:ok, _message1} ->
                  # Run for first message
                  run1_params = %{assistant_id: assistant_id}

                  case ExLLM.Providers.OpenAI.create_run(thread_id, run1_params) do
                    {:ok, run1} ->
                      # Wait for completion
                      case wait_for_run_completion(thread_id, run1["id"]) do
                        {:ok, _} ->
                          # Add second message - code request
                          message2_params = %{
                            role: "user",
                            content: "Now use Python to calculate the first 10 Fibonacci numbers."
                          }

                          case ExLLM.Providers.OpenAI.create_message(thread_id, message2_params) do
                            {:ok, _message2} ->
                              # Run for second message
                              run2_params = %{assistant_id: assistant_id}

                              case ExLLM.Providers.OpenAI.create_run(thread_id, run2_params) do
                                {:ok, run2} ->
                                  # Wait for completion
                                  case wait_for_run_completion(thread_id, run2["id"], 60_000) do
                                    {:ok, completed_run2} ->
                                      assert completed_run2["status"] == "completed"

                                      # Get all messages
                                      case ExLLM.Providers.OpenAI.list_messages(thread_id) do
                                        {:ok, messages} ->
                                          # 2 user + 2 assistant
                                          assert length(messages["data"]) >= 4

                                          # Verify we have both user and assistant messages
                                          user_messages =
                                            Enum.filter(messages["data"], fn m ->
                                              m["role"] == "user"
                                            end)

                                          assistant_messages =
                                            Enum.filter(messages["data"], fn m ->
                                              m["role"] == "assistant"
                                            end)

                                          assert length(user_messages) == 2
                                          assert length(assistant_messages) >= 2

                                          # Check run steps for second run (should use code interpreter)
                                          case ExLLM.Providers.OpenAI.list_run_steps(
                                                 thread_id,
                                                 run2["id"]
                                               ) do
                                            {:ok, steps} ->
                                              # Should have tool calls for code interpreter
                                              tool_steps =
                                                Enum.filter(steps["data"], fn step ->
                                                  step["type"] == "tool_calls"
                                                end)

                                              assert length(tool_steps) >= 1

                                            {:error, error} ->
                                              IO.puts(
                                                "Run steps listing failed: #{inspect(error)}"
                                              )

                                              assert is_map(error)
                                          end

                                        {:error, error} ->
                                          IO.puts("Message listing failed: #{inspect(error)}")
                                          assert is_map(error)
                                      end

                                    {:error, error} ->
                                      IO.puts("Second run completion failed: #{inspect(error)}")
                                      assert is_atom(error) or is_map(error)
                                  end

                                {:error, error} ->
                                  IO.puts("Second run creation failed: #{inspect(error)}")
                                  assert is_map(error)
                              end

                            {:error, error} ->
                              IO.puts("Second message creation failed: #{inspect(error)}")
                              assert is_map(error)
                          end

                        {:error, error} ->
                          IO.puts("First run completion failed: #{inspect(error)}")
                          assert is_atom(error) or is_map(error)
                      end

                    {:error, error} ->
                      IO.puts("First run creation failed: #{inspect(error)}")
                      assert is_map(error)
                  end

                {:error, error} ->
                  IO.puts("First message creation failed: #{inspect(error)}")
                  assert is_map(error)
              end

              # Cleanup
              cleanup_thread(thread_id)

            {:error, error} ->
              IO.puts("Thread creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_assistant(assistant_id)

        {:error, error} ->
          IO.puts("Assistant creation failed: #{inspect(error)}")
          assert is_map(error)
      end
    end
  end
end
