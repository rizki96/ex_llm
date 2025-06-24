defmodule ExLLM.Pipelines.StandardProvider do
  @moduledoc """
  Assembles and runs a standard pipeline for provider execution.

  This module provides helper functions to construct and execute a standard
  pipeline for processing LLM requests. It encapsulates the common flow of
  validation, configuration, execution, and telemetry, while allowing
  individual providers to inject their specific request-building and
  response-parsing logic.

  This approach promotes code reuse and ensures a consistent execution
  model across all providers.

  ## Standard Pipeline Flow

  The pipeline constructed by this module follows these steps, wrapped in
  `ExLLM.Plugs.TelemetryMiddleware` for instrumentation:

  1. `ExLLM.Plugs.ValidateProvider`: Ensures the provider is supported.
  2. `ExLLM.Plugs.ValidateMessages`: Validates the format of input messages.
  3. `ExLLM.Plugs.FetchConfiguration`: Fetches provider configuration and API keys.
  4. **Provider-Specific `build_request` plug**: Transforms the request into the provider's native format.
  5. **Authentication plug** (optional): Handles provider-specific authentication (e.g., `ExLLM.Plugs.AWSAuth` for AWS SigV4).
  6. **Execution plug**: Either `ExLLM.Plugs.ExecuteRequest` for HTTP APIs or a custom plug (e.g., `ExLLM.Plugs.ExecuteLocal` for local models).
  7. **Provider-Specific `stream_parse_response` plug** (optional): Handles streaming responses if provided.
  8. **Provider-Specific `parse_response` plug**: Parses the response into a standardized `ExLLM.Response`.

  ## Usage

  Providers typically define their `chat/2` function by calling `run/4` from this
  module, passing in their specific plugs.

      defmodule ExLLM.Providers.SomeProvider do
        def chat(messages, opts \\ []) do
          provider_plugs = [
            build_request: {ExLLM.Providers.SomeProvider.BuildRequest, []},
            parse_response: {ExLLM.Providers.SomeProvider.ParseResponse, []}
          ]

          ExLLM.Pipelines.StandardProvider.run(:some_provider, messages, opts, provider_plugs)
        end
      end
  """

  alias ExLLM.Pipeline
  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs

  @doc """
  Creates a `Request` struct and runs it through the standard pipeline.

  This is the primary entry point for providers. It simplifies the process of
  creating a request and executing the full pipeline.

  ## Parameters

    - `provider`: The atom identifying the provider (e.g., `:openai`).
    - `messages`: The list of message maps for the chat completion.
    - `opts`: A keyword list of options passed to the request.
    - `provider_plugs`: A keyword list with the following keys:
      - `:build_request` (required): The plug for building the provider-specific request.
      - `:parse_response` (required): The plug for parsing the provider's response.

  ## Returns

  The final `ExLLM.Pipeline.Request` struct after the pipeline has run. The
  result can be extracted based on the `request.state`.
  """
  @spec run(atom(), list(), keyword(), keyword()) :: Request.t()
  def run(provider, messages, opts, provider_plugs) do
    pipeline = build(provider_plugs)
    request = Request.new(provider, messages, opts)
    Pipeline.run(request, pipeline)
  end

  @doc """
  Builds the standard provider pipeline with provider-specific plugs.

  This function is useful for cases where you need to inspect the pipeline or
  compose it with other plugs before running it. In most cases, `run/4` is
  more convenient.

  ## Parameters

    - `provider_plugs`: A keyword list with the following keys:
      - `:build_request` (required): The plug for building the provider-specific request.
      - `:parse_response` (required): The plug for parsing the provider's response.
      - `:execute_request` (optional): Custom execution plug (e.g., for local models).
      - `:auth_request` (optional): Authentication plug (e.g., AWS SigV4 signing).
      - `:stream_parse_response` (optional): The plug for parsing streaming responses.

  ## Returns

  A `t:ExLLM.Pipeline.pipeline/0` definition that can be executed by `ExLLM.Pipeline.run/2`.
  """
  @spec build(keyword()) :: Pipeline.pipeline()
  def build(provider_plugs) do
    build_request_plug = Keyword.fetch!(provider_plugs, :build_request)
    parse_response_plug = Keyword.fetch!(provider_plugs, :parse_response)

    execute_request_plug =
      Keyword.get(provider_plugs, :execute_request, {Plugs.ExecuteRequest, []})

    stream_parse_response_plug = Keyword.get(provider_plugs, :stream_parse_response)

    # Get authentication plug if provided
    auth_plug = Keyword.get(provider_plugs, :auth_request)

    # Add Tesla client plug only for HTTP-based providers (not local providers)
    tesla_client_plug =
      case execute_request_plug do
        {Plugs.ExecuteRequest, _} -> {Plugs.BuildTeslaClient, []}
        _ -> nil
      end

    # The main pipeline that will be wrapped by Telemetry
    inner_pipeline =
      [
        {Plugs.ValidateProvider, []},
        {Plugs.ValidateMessages, []},
        {Plugs.FetchConfiguration, []},
        build_request_plug,
        # Build Tesla client for HTTP requests (only when using ExecuteRequest)
        tesla_client_plug,
        # Add authentication plug before execution if provided
        auth_plug,
        # Use custom execute plug if provided, otherwise use default HTTP execution
        execute_request_plug,
        # Include streaming parser if available
        stream_parse_response_plug,
        # Regular parser runs after streaming parser (for non-streaming) or execute
        parse_response_plug
      ]
      |> Enum.reject(&is_nil/1)

    # The final pipeline with Telemetry wrapping everything
    [
      {Plugs.TelemetryMiddleware,
       %{
         event_name: [:ex_llm, :provider, :execution],
         pipeline: inner_pipeline
       }}
    ]
  end
end
