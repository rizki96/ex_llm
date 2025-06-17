defmodule ExLLM.Providers.Gemini.Live do
  @moduledoc """
  Google Gemini Live API implementation using WebSockets.

  The Live API enables real-time bidirectional communication with Gemini models,
  supporting text, audio, and video inputs with streaming responses.

  ## Features

  - Real-time text, audio, and video streaming
  - Bidirectional communication with interruption support
  - Tool/function calling in real-time sessions
  - Session resumption capabilities
  - Activity detection and management
  - Audio transcription for both input and output

  ## Usage

      # Start a live session
      config = %{
        model: "models/gemini-2.5-flash-preview-05-20",
        generation_config: %{
          temperature: 0.7,
          response_modalities: ["TEXT", "AUDIO"]
        },
        system_instruction: "You are a helpful assistant."
      }
      
      {:ok, session} = Live.start_session(config, api_key: "your-api-key")
      
      # Send text message
      :ok = Live.send_text(session, "Hello, how are you?")
      
      # Send audio data
      :ok = Live.send_audio(session, audio_chunk)
      
      # Listen for responses
      receive do
        {:live_response, :server_content, content} ->
          IO.puts("Model response: \#{content.model_turn_content}")
        {:live_response, :tool_call, tool_call} ->
          # Handle tool call
          response = execute_tool(tool_call)
          Live.send_tool_response(session, response)
      end
      
      # Close session
      Live.close_session(session)

  ## Authentication

  The Live API supports both API key and OAuth2 authentication:

  - **API key**: Passed as query parameter in WebSocket URL
  - **OAuth2**: Passed as Authorization header during WebSocket handshake
  """

  require Logger
  use GenServer

  # Struct definitions for Live API messages

  defmodule GenerationConfig do
    @moduledoc "Generation configuration for Live API"

    defstruct [
      :candidate_count,
      :max_output_tokens,
      :temperature,
      :top_p,
      :top_k,
      :presence_penalty,
      :frequency_penalty,
      :response_modalities,
      :speech_config,
      :media_resolution
    ]

    @type t :: %__MODULE__{
            candidate_count: integer() | nil,
            max_output_tokens: integer() | nil,
            temperature: float() | nil,
            top_p: float() | nil,
            top_k: integer() | nil,
            presence_penalty: float() | nil,
            frequency_penalty: float() | nil,
            response_modalities: [String.t()] | nil,
            speech_config: map() | nil,
            media_resolution: map() | nil
          }
  end

  defmodule Content do
    @moduledoc "Content structure for Live API"

    defstruct [:role, :parts]

    @type t :: %__MODULE__{
            role: String.t(),
            parts: [map()]
          }
  end

  defmodule SetupMessage do
    @moduledoc "Initial session setup message"

    defstruct [
      :model,
      :generation_config,
      :system_instruction,
      :tools,
      :realtime_input_config,
      :session_resumption,
      :context_window_compression,
      :input_audio_transcription,
      :output_audio_transcription
    ]

    @type t :: %__MODULE__{
            model: String.t(),
            generation_config: GenerationConfig.t() | nil,
            system_instruction: Content.t() | nil,
            tools: [map()] | nil,
            realtime_input_config: map() | nil,
            session_resumption: map() | nil,
            context_window_compression: map() | nil,
            input_audio_transcription: map() | nil,
            output_audio_transcription: map() | nil
          }
  end

  defmodule ClientContentMessage do
    @moduledoc "Client content message"

    defstruct [:turns, :turn_complete]

    @type t :: %__MODULE__{
            turns: [map()],
            turn_complete: boolean()
          }
  end

  defmodule RealtimeInputMessage do
    @moduledoc "Real-time input message"

    defstruct [
      :text,
      :audio,
      :video,
      :activity_start,
      :activity_end,
      :audio_stream_end
    ]

    @type t :: %__MODULE__{
            text: String.t() | nil,
            audio: map() | nil,
            video: map() | nil,
            activity_start: map() | nil,
            activity_end: map() | nil,
            audio_stream_end: boolean() | nil
          }
  end

  defmodule ToolResponseMessage do
    @moduledoc "Tool response message"

    defstruct [:function_responses]

    @type t :: %__MODULE__{
            function_responses: [map()]
          }
  end

  defmodule ServerContentMessage do
    @moduledoc "Server content message"

    defstruct [
      :generation_complete,
      :turn_complete,
      :interrupted,
      :grounding_metadata,
      :input_transcription,
      :output_transcription,
      :model_turn_content
    ]

    @type t :: %__MODULE__{
            generation_complete: boolean() | nil,
            turn_complete: boolean() | nil,
            interrupted: boolean() | nil,
            grounding_metadata: map() | nil,
            input_transcription: map() | nil,
            output_transcription: map() | nil,
            model_turn_content: Content.t() | nil
          }
  end

  defmodule ToolCallMessage do
    @moduledoc "Tool call message from server"

    defstruct [:function_calls]

    @type t :: %__MODULE__{
            function_calls: [FunctionCall.t()]
          }
  end

  defmodule FunctionCall do
    @moduledoc "Function call details"

    defstruct [:id, :name, :args]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            args: map()
          }
  end

  defmodule GoAwayMessage do
    @moduledoc "Server disconnect notification"

    defstruct [:time_left]

    @type t :: %__MODULE__{
            time_left: map()
          }
  end

  # GenServer state
  defstruct [
    :conn_pid,
    :stream_ref,
    :owner_pid,
    :api_key,
    :oauth_token,
    :status,
    :config
  ]

  @type t :: %__MODULE__{
          conn_pid: pid() | nil,
          stream_ref: reference() | nil,
          owner_pid: pid(),
          api_key: String.t() | nil,
          oauth_token: String.t() | nil,
          status: :connecting | :connected | :ready | :closed | :error,
          config: map()
        }

  # Public API

  @doc """
  Starts a new Live API session.

  ## Parameters

  - `config` - Session configuration containing model and parameters
  - `opts` - Authentication and options

  ## Options

  - `:api_key` - Google API key for authentication
  - `:oauth_token` - OAuth2 token for authentication (alternative to API key)
  - `:owner_pid` - Process to receive session messages (defaults to caller)

  ## Returns

  - `{:ok, session_pid}` - Session GenServer process
  - `{:error, reason}` - Error details

  ## Examples

      config = %{
        model: "models/gemini-2.5-flash-preview-05-20",
        generation_config: %{
          temperature: 0.7,
          response_modalities: ["TEXT", "AUDIO"]
        }
      }
      
      {:ok, session} = Live.start_session(config, api_key: "your-api-key")
  """
  @spec start_session(map(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_session(config, opts \\ []) do
    with :ok <- validate_setup_config(config),
         :ok <- validate_auth(opts) do
      owner_pid = Keyword.get(opts, :owner_pid, self())
      api_key = Keyword.get(opts, :api_key)
      oauth_token = Keyword.get(opts, :oauth_token)

      GenServer.start_link(__MODULE__, %{
        config: config,
        owner_pid: owner_pid,
        api_key: api_key,
        oauth_token: oauth_token
      })
    end
  end

  @doc """
  Sends a text message to the session.

  ## Parameters

  - `session` - Session process pid
  - `text` - Text content to send
  - `opts` - Options

  ## Options

  - `:turn_complete` - Whether this completes the user's turn (default: true)
  """
  @spec send_text(pid(), String.t(), keyword()) :: :ok | {:error, term()}
  def send_text(session, text, opts \\ []) do
    turn_complete = Keyword.get(opts, :turn_complete, true)

    turns = [%{role: "user", parts: [%{text: text}]}]
    message = build_client_content_message(turns, turn_complete)

    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Sends real-time text input to the session.

  This is different from send_text/3 as it's designed for streaming text input
  that doesn't interrupt model generation.
  """
  @spec send_realtime_text(pid(), String.t()) :: :ok | {:error, term()}
  def send_realtime_text(session, text) do
    message = build_realtime_input_message(%{text: text})
    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Sends audio data to the session.

  ## Parameters

  - `session` - Session process pid
  - `audio_data` - Binary audio data
  """
  @spec send_audio(pid(), binary()) :: :ok | {:error, term()}
  def send_audio(session, audio_data) do
    message = build_realtime_input_message(%{audio: audio_data})
    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Sends video data to the session.

  ## Parameters

  - `session` - Session process pid
  - `video_data` - Binary video data
  """
  @spec send_video(pid(), binary()) :: :ok | {:error, term()}
  def send_video(session, video_data) do
    message = build_realtime_input_message(%{video: video_data})
    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Sends activity start signal to the session.

  This is used when automatic activity detection is disabled.
  """
  @spec send_activity_start(pid()) :: :ok | {:error, term()}
  def send_activity_start(session) do
    message = build_realtime_input_message(%{activity_start: true})
    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Sends activity end signal to the session.

  This is used when automatic activity detection is disabled.
  """
  @spec send_activity_end(pid()) :: :ok | {:error, term()}
  def send_activity_end(session) do
    message = build_realtime_input_message(%{activity_end: true})
    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Sends tool/function response to the session.

  ## Parameters

  - `session` - Session process pid
  - `function_responses` - List of function response objects
  """
  @spec send_tool_response(pid(), [map()]) :: :ok | {:error, term()}
  def send_tool_response(session, function_responses) do
    message = build_tool_response_message(function_responses)
    GenServer.call(session, {:send_message, message})
  end

  @doc """
  Closes the Live API session.
  """
  @spec close_session(pid()) :: :ok
  def close_session(session) do
    GenServer.call(session, :close)
  end

  # Message building functions

  @doc false
  def build_websocket_url(api_key, _oauth_token \\ nil) do
    base_url =
      "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    if api_key do
      "#{base_url}?key=#{api_key}"
    else
      base_url
    end
  end

  @doc false
  def build_setup_message(config) do
    setup = %SetupMessage{
      model: config[:model],
      generation_config: build_generation_config(config[:generation_config]),
      system_instruction: build_system_instruction(config[:system_instruction]),
      tools: config[:tools],
      realtime_input_config: config[:realtime_input_config],
      session_resumption: config[:session_resumption],
      context_window_compression: config[:context_window_compression],
      input_audio_transcription: config[:input_audio_transcription],
      output_audio_transcription: config[:output_audio_transcription]
    }

    %{setup: setup}
  end

  @doc false
  def build_client_content_message(turns, turn_complete) do
    content = %ClientContentMessage{
      turns: turns,
      turn_complete: turn_complete
    }

    %{client_content: content}
  end

  @doc false
  def build_realtime_input_message(input) do
    realtime_input = %RealtimeInputMessage{
      text: input[:text],
      audio: if(input[:audio], do: %{data: input[:audio]}, else: nil),
      video: if(input[:video], do: %{data: input[:video]}, else: nil),
      activity_start: if(input[:activity_start], do: %{}, else: nil),
      activity_end: if(input[:activity_end], do: %{}, else: nil),
      audio_stream_end: input[:audio_stream_end]
    }

    %{realtime_input: realtime_input}
  end

  @doc false
  def build_tool_response_message(function_responses) do
    tool_response = %ToolResponseMessage{
      function_responses: function_responses
    }

    %{tool_response: tool_response}
  end

  # Message parsing functions

  @doc false
  def parse_server_message(message) do
    cond do
      Map.has_key?(message, "setupComplete") ->
        {:setup_complete, message["setupComplete"]}

      Map.has_key?(message, "serverContent") ->
        content = parse_server_content(message["serverContent"])
        {:server_content, content}

      Map.has_key?(message, "toolCall") ->
        tool_call = parse_tool_call(message["toolCall"])
        {:tool_call, tool_call}

      Map.has_key?(message, "toolCallCancellation") ->
        {:tool_call_cancellation, message["toolCallCancellation"]}

      Map.has_key?(message, "goAway") ->
        go_away = %GoAwayMessage{time_left: message["goAway"]["timeLeft"]}
        {:go_away, go_away}

      Map.has_key?(message, "sessionResumptionUpdate") ->
        {:session_resumption_update, message["sessionResumptionUpdate"]}

      true ->
        {:unknown, message}
    end
  end

  # Validation functions

  @doc false
  def validate_setup_config(config) do
    cond do
      not Map.has_key?(config, :model) ->
        {:error, "model is required in setup config"}

      config[:model] == "" or is_nil(config[:model]) ->
        {:error, "model cannot be empty"}

      config[:generation_config] ->
        case validate_generation_config(config[:generation_config]) do
          :ok -> :ok
          {:error, message} -> {:error, message}
        end

      true ->
        :ok
    end
  end

  @doc false
  def validate_realtime_input(input) do
    input_types = [:text, :audio, :video, :activity_start, :activity_end, :audio_stream_end]
    provided_inputs = Enum.filter(input_types, &Map.has_key?(input, &1))

    cond do
      provided_inputs == [] ->
        {:error, "at least one input type must be provided"}

      length(provided_inputs) > 1 and not only_activity_signals?(provided_inputs) ->
        {:error, "only one input type can be provided at a time"}

      true ->
        :ok
    end
  end

  # GenServer callbacks

  @impl true
  def init(%{config: config, owner_pid: owner_pid, api_key: api_key, oauth_token: oauth_token}) do
    state = %__MODULE__{
      owner_pid: owner_pid,
      api_key: api_key,
      oauth_token: oauth_token,
      status: :connecting,
      config: config
    }

    # Start WebSocket connection
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_websocket(state) do
      {:ok, conn_pid, stream_ref} ->
        # Send setup message
        setup_message = build_setup_message(state.config)
        send_websocket_message(conn_pid, stream_ref, setup_message)

        {:noreply, %{state | conn_pid: conn_pid, stream_ref: stream_ref, status: :connected}}

      {:error, reason} ->
        send(state.owner_pid, {:live_error, reason})
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:gun_ws, conn_pid, stream_ref, {:text, data}}, state)
      when conn_pid == state.conn_pid and stream_ref == state.stream_ref do
    case Jason.decode(data) do
      {:ok, message} ->
        parsed = parse_server_message(message)

        # Update status if setup complete
        new_status = if elem(parsed, 0) == :setup_complete, do: :ready, else: state.status

        # Send message to owner
        send(state.owner_pid, {:live_response, elem(parsed, 0), elem(parsed, 1)})

        {:noreply, %{state | status: new_status}}

      {:error, reason} ->
        Logger.error("Failed to decode WebSocket message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gun_ws, conn_pid, stream_ref, {:close, code, reason}}, state)
      when conn_pid == state.conn_pid and stream_ref == state.stream_ref do
    Logger.info("WebSocket closed: #{code} - #{reason}")
    send(state.owner_pid, {:live_closed, code, reason})

    {:noreply, %{state | status: :closed}}
  end

  @impl true
  def handle_info({:gun_down, conn_pid, :ws, reason, _killed_streams}, state)
      when conn_pid == state.conn_pid do
    Logger.error("WebSocket connection down: #{inspect(reason)}")
    send(state.owner_pid, {:live_error, reason})

    {:noreply, %{state | status: :error}}
  end

  @impl true
  def handle_call({:send_message, message}, _from, %{status: :ready} = state) do
    case send_websocket_message(state.conn_pid, state.stream_ref, message) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:send_message, _message}, _from, state) do
    {:reply, {:error, "session not ready"}, state}
  end

  @impl true
  def handle_call(:close, _from, state) do
    if state.conn_pid do
      :gun.ws_send(state.conn_pid, state.stream_ref, :close)
      :gun.close(state.conn_pid)
    end

    {:stop, :normal, :ok, %{state | status: :closed}}
  end

  # Private helper functions

  defp validate_auth(opts) do
    api_key = Keyword.get(opts, :api_key)
    oauth_token = Keyword.get(opts, :oauth_token)

    if api_key || oauth_token do
      :ok
    else
      {:error, "either api_key or oauth_token must be provided"}
    end
  end

  defp validate_generation_config(config) do
    cond do
      config[:temperature] && (config[:temperature] < 0 or config[:temperature] > 2) ->
        {:error, "temperature must be between 0 and 2"}

      config[:response_modalities] && not valid_response_modalities?(config[:response_modalities]) ->
        {:error, "response_modalities must contain only TEXT and/or AUDIO"}

      true ->
        :ok
    end
  end

  defp valid_response_modalities?(modalities) do
    valid_modalities = ["TEXT", "AUDIO"]
    Enum.all?(modalities, &(&1 in valid_modalities))
  end

  defp only_activity_signals?(inputs) do
    activity_signals = [:activity_start, :activity_end]
    Enum.all?(inputs, &(&1 in activity_signals))
  end

  defp build_generation_config(nil), do: nil

  defp build_generation_config(config) do
    %GenerationConfig{
      candidate_count: config[:candidate_count],
      max_output_tokens: config[:max_output_tokens],
      temperature: config[:temperature],
      top_p: config[:top_p],
      top_k: config[:top_k],
      presence_penalty: config[:presence_penalty],
      frequency_penalty: config[:frequency_penalty],
      response_modalities: config[:response_modalities],
      speech_config: config[:speech_config],
      media_resolution: config[:media_resolution]
    }
  end

  defp build_system_instruction(nil), do: nil

  defp build_system_instruction(instruction) when is_binary(instruction) do
    %Content{
      role: "system",
      parts: [%{text: instruction}]
    }
  end

  defp build_system_instruction(instruction), do: instruction

  defp parse_server_content(content) do
    %ServerContentMessage{
      generation_complete: content["generationComplete"],
      turn_complete: content["turnComplete"],
      interrupted: content["interrupted"],
      grounding_metadata: content["groundingMetadata"],
      input_transcription: parse_transcription(content["inputTranscription"]),
      output_transcription: parse_transcription(content["outputTranscription"]),
      model_turn_content: parse_content(content["modelTurnContent"])
    }
  end

  defp parse_tool_call(tool_call) do
    function_calls =
      Enum.map(tool_call["functionCalls"] || [], fn call ->
        %FunctionCall{
          id: call["id"],
          name: call["name"],
          args: call["args"]
        }
      end)

    %ToolCallMessage{function_calls: function_calls}
  end

  defp parse_transcription(nil), do: nil

  defp parse_transcription(transcription) do
    %{text: transcription["text"]}
  end

  defp parse_content(nil), do: nil

  defp parse_content(content) do
    parts =
      case content["parts"] do
        nil ->
          []

        parts when is_list(parts) ->
          Enum.map(parts, fn part ->
            if is_map(part) and Map.has_key?(part, "text") do
              %{text: part["text"]}
            else
              part
            end
          end)
      end

    %Content{
      role: content["role"],
      parts: parts
    }
  end

  defp connect_websocket(state) do
    url = build_websocket_url(state.api_key, state.oauth_token)
    uri = URI.parse(url)

    # Start Gun connection
    opts = %{
      protocols: [:http],
      transport: :tls
    }

    case :gun.open(String.to_charlist(uri.host), uri.port || 443, opts) do
      {:ok, conn_pid} ->
        case :gun.await_up(conn_pid) do
          {:ok, :http} ->
            # Build headers
            headers = build_headers(state.oauth_token)

            # Upgrade to WebSocket
            stream_ref =
              :gun.ws_upgrade(
                conn_pid,
                uri.path <> ((uri.query && "?#{uri.query}") || ""),
                headers
              )

            case :gun.await(conn_pid, stream_ref) do
              {:upgrade, ["websocket"], _headers} ->
                {:ok, conn_pid, stream_ref}

              error ->
                :gun.close(conn_pid)
                {:error, {:ws_upgrade_failed, error}}
            end

          error ->
            :gun.close(conn_pid)
            {:error, {:connection_failed, error}}
        end

      error ->
        {:error, {:gun_open_failed, error}}
    end
  end

  defp build_headers(nil), do: []

  defp build_headers(oauth_token) do
    [{"authorization", "Bearer #{oauth_token}"}]
  end

  defp send_websocket_message(conn_pid, stream_ref, message) do
    case Jason.encode(message) do
      {:ok, json} ->
        :gun.ws_send(conn_pid, stream_ref, {:text, json})
        :ok

      {:error, reason} ->
        {:error, {:encode_failed, reason}}
    end
  end
end
