defmodule ExLLM.Adapters.Gemini.LiveTest do
  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Live

  @moduletag :gemini_live

  describe "connection management" do
    test "build_websocket_url/1 constructs correct WebSocket URL" do
      url = Live.build_websocket_url("test-api-key")
      
      assert url == "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=test-api-key"
    end

    test "build_websocket_url/1 with OAuth2" do
      url = Live.build_websocket_url(nil, "oauth-token")
      
      assert url == "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    end
  end

  describe "message building" do
    test "build_setup_message/1 creates proper setup message" do
      config = %{
        model: "models/gemini-2.5-flash-preview-05-20",
        generation_config: %{
          temperature: 0.7,
          max_output_tokens: 1000,
          response_modalities: ["TEXT", "AUDIO"]
        },
        system_instruction: "You are a helpful assistant.",
        tools: []
      }

      message = Live.build_setup_message(config)

      assert %{setup: setup} = message
      assert setup.model == "models/gemini-2.5-flash-preview-05-20"
      assert setup.generation_config.temperature == 0.7
      assert setup.generation_config.max_output_tokens == 1000
      assert setup.generation_config.response_modalities == ["TEXT", "AUDIO"]
      assert setup.system_instruction.parts == [%{text: "You are a helpful assistant."}]
      assert setup.tools == []
    end

    test "build_setup_message/1 with minimal config" do
      config = %{model: "models/gemini-2.5-flash-preview-05-20"}

      message = Live.build_setup_message(config)

      assert %{setup: setup} = message
      assert setup.model == "models/gemini-2.5-flash-preview-05-20"
      assert is_nil(setup.generation_config)
      assert is_nil(setup.system_instruction)
      assert is_nil(setup.tools)
    end

    test "build_client_content_message/2 creates client content message" do
      turns = [
        %{role: "user", parts: [%{text: "Hello, how are you?"}]}
      ]
      
      message = Live.build_client_content_message(turns, true)

      assert %{client_content: content} = message
      assert content.turns == turns
      assert content.turn_complete == true
    end

    test "build_realtime_input_message/1 creates text realtime input" do
      message = Live.build_realtime_input_message(%{text: "Hello world"})

      assert %{realtime_input: input} = message
      assert input.text == "Hello world"
      assert is_nil(input.audio)
      assert is_nil(input.video)
    end

    test "build_realtime_input_message/1 creates audio realtime input" do
      audio_data = <<1, 2, 3, 4>>
      message = Live.build_realtime_input_message(%{audio: audio_data})

      assert %{realtime_input: input} = message
      assert input.audio.data == audio_data
      assert is_nil(input.text)
      assert is_nil(input.video)
    end

    test "build_realtime_input_message/1 creates activity signals" do
      message = Live.build_realtime_input_message(%{activity_start: true})

      assert %{realtime_input: input} = message
      assert input.activity_start == %{}
      assert is_nil(input.text)
      assert is_nil(input.audio)

      message = Live.build_realtime_input_message(%{activity_end: true})

      assert %{realtime_input: input} = message
      assert input.activity_end == %{}
    end

    test "build_tool_response_message/1 creates tool response message" do
      function_responses = [
        %{
          id: "call_123",
          name: "get_weather",
          response: %{temperature: 72, conditions: "sunny"}
        }
      ]

      message = Live.build_tool_response_message(function_responses)

      assert %{tool_response: response} = message
      assert response.function_responses == function_responses
    end
  end

  describe "message parsing" do
    test "parse_server_message/1 parses setup complete message" do
      message = %{"setupComplete" => %{}}

      result = Live.parse_server_message(message)

      assert {:setup_complete, %{}} = result
    end

    test "parse_server_message/1 parses server content message" do
      message = %{
        "serverContent" => %{
          "modelTurnContent" => %{
            "role" => "model",
            "parts" => [%{"text" => "Hello! I'm doing well, thank you."}]
          },
          "turnComplete" => true,
          "generationComplete" => true
        }
      }

      result = Live.parse_server_message(message)

      assert {:server_content, content} = result
      assert content.model_turn_content.role == "model"
      assert content.model_turn_content.parts == [%{text: "Hello! I'm doing well, thank you."}]
      assert content.turn_complete == true
      assert content.generation_complete == true
    end

    test "parse_server_message/1 parses tool call message" do
      message = %{
        "toolCall" => %{
          "functionCalls" => [
            %{
              "id" => "call_123",
              "name" => "get_weather",
              "args" => %{"location" => "San Francisco"}
            }
          ]
        }
      }

      result = Live.parse_server_message(message)

      assert {:tool_call, tool_call} = result
      assert length(tool_call.function_calls) == 1
      [call] = tool_call.function_calls
      assert call.id == "call_123"
      assert call.name == "get_weather"
      assert call.args == %{"location" => "San Francisco"}
    end

    test "parse_server_message/1 parses transcription message" do
      message = %{
        "serverContent" => %{
          "inputTranscription" => %{
            "text" => "Hello there"
          }
        }
      }

      result = Live.parse_server_message(message)

      assert {:server_content, content} = result
      assert content.input_transcription.text == "Hello there"
    end

    test "parse_server_message/1 parses go away message" do
      message = %{
        "goAway" => %{
          "timeLeft" => %{"seconds" => 30}
        }
      }

      result = Live.parse_server_message(message)

      assert {:go_away, go_away} = result
      assert go_away.time_left == %{"seconds" => 30}
    end

    test "parse_server_message/1 handles unknown message types" do
      message = %{
        "unknownField" => %{"data" => "test"}
      }

      result = Live.parse_server_message(message)

      assert {:unknown, ^message} = result
    end
  end

  describe "validation" do
    test "validate_setup_config/1 validates required model" do
      # Valid config
      config = %{model: "models/gemini-2.5-flash-preview-05-20"}
      assert :ok = Live.validate_setup_config(config)

      # Missing model
      config = %{}
      assert {:error, message} = Live.validate_setup_config(config)
      assert String.contains?(message, "model is required")

      # Empty model
      config = %{model: ""}
      assert {:error, message} = Live.validate_setup_config(config)
      assert String.contains?(message, "model cannot be empty")
    end

    test "validate_setup_config/1 validates generation config" do
      # Valid generation config
      config = %{
        model: "models/gemini-2.5-flash-preview-05-20",
        generation_config: %{
          temperature: 0.7,
          max_output_tokens: 1000,
          response_modalities: ["TEXT"]
        }
      }
      assert :ok = Live.validate_setup_config(config)

      # Invalid temperature
      config = %{
        model: "models/gemini-2.5-flash-preview-05-20",
        generation_config: %{temperature: -1}
      }
      assert {:error, message} = Live.validate_setup_config(config)
      assert String.contains?(message, "temperature must be between 0 and 2")

      # Invalid response modalities
      config = %{
        model: "models/gemini-2.5-flash-preview-05-20",
        generation_config: %{response_modalities: ["INVALID"]}
      }
      assert {:error, message} = Live.validate_setup_config(config)
      assert String.contains?(message, "response_modalities must contain only TEXT and/or AUDIO")
    end

    test "validate_realtime_input/1 validates input types" do
      # Valid text input
      assert :ok = Live.validate_realtime_input(%{text: "Hello"})

      # Valid audio input
      assert :ok = Live.validate_realtime_input(%{audio: <<1, 2, 3>>})

      # Valid activity signals
      assert :ok = Live.validate_realtime_input(%{activity_start: true})
      assert :ok = Live.validate_realtime_input(%{activity_end: true})

      # Empty input
      assert {:error, message} = Live.validate_realtime_input(%{})
      assert String.contains?(message, "at least one input type must be provided")

      # Multiple inputs (not allowed)
      assert {:error, message} = Live.validate_realtime_input(%{text: "Hello", audio: <<1, 2>>})
      assert String.contains?(message, "only one input type can be provided at a time")
    end
  end

  describe "struct definitions" do
    test "SetupMessage struct" do
      setup = %Live.SetupMessage{
        model: "models/gemini-2.5-flash-preview-05-20",
        generation_config: %Live.GenerationConfig{temperature: 0.7},
        system_instruction: %Live.Content{parts: [%{text: "Test"}]}
      }

      assert setup.model == "models/gemini-2.5-flash-preview-05-20"
      assert setup.generation_config.temperature == 0.7
      assert setup.system_instruction.parts == [%{text: "Test"}]
    end

    test "ClientContentMessage struct" do
      content = %Live.ClientContentMessage{
        turns: [%{role: "user", parts: [%{text: "Hello"}]}],
        turn_complete: true
      }

      assert length(content.turns) == 1
      assert content.turn_complete == true
    end

    test "RealtimeInputMessage struct" do
      # Text input
      input = %Live.RealtimeInputMessage{text: "Hello world"}
      assert input.text == "Hello world"
      assert is_nil(input.audio)

      # Audio input
      audio_data = <<1, 2, 3, 4>>
      input = %Live.RealtimeInputMessage{audio: %{data: audio_data}}
      assert input.audio.data == audio_data
      assert is_nil(input.text)

      # Activity signals
      input = %Live.RealtimeInputMessage{activity_start: %{}}
      assert input.activity_start == %{}
    end

    test "ServerContentMessage struct" do
      content = %Live.ServerContentMessage{
        model_turn_content: %Live.Content{
          role: "model",
          parts: [%{text: "Response"}]
        },
        turn_complete: true,
        generation_complete: true,
        interrupted: false
      }

      assert content.model_turn_content.role == "model"
      assert content.turn_complete == true
      assert content.generation_complete == true
      assert content.interrupted == false
    end

    test "ToolCallMessage struct" do
      tool_call = %Live.ToolCallMessage{
        function_calls: [
          %Live.FunctionCall{
            id: "call_123",
            name: "get_weather",
            args: %{"location" => "NYC"}
          }
        ]
      }

      assert length(tool_call.function_calls) == 1
      call = hd(tool_call.function_calls)
      assert call.id == "call_123"
      assert call.name == "get_weather"
      assert call.args == %{"location" => "NYC"}
    end
  end
end