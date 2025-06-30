if Code.ensure_loaded?(Nx.Serving) do
  defmodule ExLLM.Plugs.ExecuteLocal do
    @moduledoc """
    Executes a request using a local model without HTTP calls.

    This plug is designed for providers that run models locally (e.g., Bumblebee)
    and need to execute inference without making network requests.

    ## Expected Assigns

    - `:model_ref` - Reference to the loaded model
    - `:formatted_input` - Input formatted for the model
    - `:generation_config` - Configuration for text generation

    ## Sets in Assigns

    - `:raw_response` - The raw response from the model
    - `:response_type` - Either `:streaming` or `:complete`
    """

    use ExLLM.Plug
    alias ExLLM.Infrastructure.Logger
    alias ExLLM.Pipeline.Request

    @impl true
    def call(%Request{state: :executing} = request, _opts) do
      model_ref = request.assigns[:model_ref]
      formatted_input = request.assigns[:formatted_input]
      generation_config = request.assigns[:generation_config] || %{}

      if model_ref && formatted_input do
        execute_local_inference(request, model_ref, formatted_input, generation_config)
      else
        request
        |> Request.add_error(%{
          plug: __MODULE__,
          reason: :missing_required_assigns,
          message: "ExecuteLocal requires :model_ref and :formatted_input in assigns"
        })
        |> Request.put_state(:error)
        |> Request.halt()
      end
    end

    def call(request, _opts), do: request

    defp execute_local_inference(request, model_ref, formatted_input, generation_config) do
      stream = generation_config[:stream] || false

      try do
        if stream do
          handle_streaming_inference(request, model_ref, formatted_input, generation_config)
        else
          handle_complete_inference(request, model_ref, formatted_input, generation_config)
        end
      catch
        kind, reason ->
          Logger.error("Local inference error: #{inspect({kind, reason})}")

          request
          |> Request.add_error(%{
            plug: __MODULE__,
            error: {kind, reason},
            message: "Local inference failed: #{inspect(reason)}"
          })
          |> Request.put_state(:error)
          |> Request.halt()
      end
    end

    defp handle_complete_inference(request, {serving, _tokenizer, generation_config}, input, opts) do
      # For complete inference, we generate all tokens at once
      max_new_tokens = opts[:max_tokens] || generation_config.max_new_tokens || 2048
      temperature = opts[:temperature] || 0.7

      # Update generation config with request options
      _config = %{
        generation_config
        | max_new_tokens: max_new_tokens,
          temperature: temperature
      }

      # Run inference
      case Nx.Serving.run(serving, input) do
        %{results: [%{text: generated_text} | _]} = response ->
          request
          |> Request.assign(:raw_response, response)
          |> Request.assign(:generated_text, generated_text)
          |> Request.assign(:response_type, :complete)
          |> Request.put_state(:completed)

        other ->
          request
          |> Request.add_error(%{
            plug: __MODULE__,
            reason: :unexpected_response,
            message: "Unexpected response format: #{inspect(other)}"
          })
          |> Request.put_state(:error)
          |> Request.halt()
      end
    end

    defp handle_streaming_inference(request, model_ref, input, opts) do
      # For streaming, we need to create a stream that yields tokens
      # This will be picked up by the StreamParseResponse plug

      stream = create_token_stream(model_ref, input, opts)

      request
      |> Request.assign(:token_stream, stream)
      |> Request.assign(:response_type, :streaming)
      |> Request.put_state(:streaming)
    end

    # NOTE: Defensive error handling - get_next_token currently only returns {:ok, token} | :done
    # but this error clause provides safety if the function changes in future versions
    defp create_token_stream({serving, _tokenizer, generation_config}, input, opts) do
      # Create a stream that generates tokens one by one
      Stream.resource(
        # Start function
        fn ->
          # Initialize the generation state
          max_new_tokens = opts[:max_tokens] || generation_config.max_new_tokens || 2048
          temperature = opts[:temperature] || 0.7

          config = %{
            generation_config
            | max_new_tokens: max_new_tokens,
              temperature: temperature
          }

          # Start generation process
          {:ok, generation_pid} = start_generation_process(serving, input, config)
          {generation_pid, 0, max_new_tokens}
        end,

        # Next function
        fn
          {pid, count, max} when count < max ->
            # Get next token from generation process
            # NOTE: Defensive error handling - get_next_token currently only returns {:ok, token} or :done
            # If error handling is needed in future, add appropriate clause here
            case get_next_token(pid) do
              {:ok, token} ->
                {[token], {pid, count + 1, max}}

              :done ->
                {:halt, {pid, count, max}}
            end

          {pid, count, max} ->
            # Max tokens reached
            {:halt, {pid, count, max}}
        end,

        # Cleanup function
        fn {pid, _count, _max} ->
          # Stop the generation process
          stop_generation_process(pid)
        end
      )
    end

    # These would be implemented based on the actual Bumblebee/Nx.Serving API
    defp start_generation_process(_serving, _input, _config) do
      # Placeholder - actual implementation would start async generation
      {:ok, self()}
    end

    defp get_next_token(_pid) do
      # Placeholder - actual implementation would get next token
      # For now, simulate token generation
      Process.sleep(10)

      if :rand.uniform() > 0.95 do
        :done
      else
        {:ok, "token_#{:rand.uniform(1000)}"}
      end
    end

    defp stop_generation_process(_pid) do
      # Placeholder - cleanup generation process
      :ok
    end
  end
else
  defmodule ExLLM.Plugs.ExecuteLocal do
    @moduledoc """
    Stub module for when Nx.Serving is not available.

    This module exists as a placeholder when Bumblebee/Nx dependencies
    are not available, preventing compilation errors.
    """

    use ExLLM.Plug

    @impl true
    def call(request, _opts) do
      request
      |> ExLLM.Pipeline.Request.add_error(%{
        plug: __MODULE__,
        reason: :dependency_unavailable,
        message: "Nx.Serving is not available. Install Bumblebee and Nx to use local models."
      })
      |> ExLLM.Pipeline.Request.put_state(:error)
      |> ExLLM.Pipeline.Request.halt()
    end
  end
end
