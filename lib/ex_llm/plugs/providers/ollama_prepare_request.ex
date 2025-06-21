defmodule ExLLM.Plugs.Providers.OllamaPrepareRequest do
  @moduledoc """
  Prepares a request for the Ollama API.

  Transforms the generic ExLLM message format into Ollama's expected
  format. Ollama has its own unique API structure that differs from
  OpenAI-compatible APIs.
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Logger

  @impl true
  def call(%Request{} = request, _opts) do
    body = build_request_body(request)

    request
    |> Map.put(:provider_request, body)
    |> Request.put_private(:provider_request_body, body)
    |> Request.assign(:request_prepared, true)
  end

  defp build_request_body(%Request{messages: messages, config: config}) do
    # Ollama uses a different format depending on the endpoint
    # For chat completions, it expects a specific structure

    body = %{
      model: config[:model] || "llama2",
      messages: Enum.map(messages, &format_message/1),
      stream: config[:stream] || false
    }

    # Add optional parameters
    body
    |> maybe_add_options(config)
    |> maybe_add_format(config)
    |> maybe_add_keep_alive(config)
    |> compact()
  end

  defp format_message(%{role: role, content: content} = message) do
    base = %{
      "role" => normalize_role(role),
      "content" => format_content(content)
    }

    # Add images if present (Ollama supports images in specific models)
    base
    |> maybe_add_images(message)
  end

  defp normalize_role("user"), do: "user"
  defp normalize_role("assistant"), do: "assistant"
  defp normalize_role("system"), do: "system"
  defp normalize_role(_), do: "user"

  defp format_content(content) when is_binary(content), do: content

  defp format_content(content) when is_list(content) do
    # Extract text parts and handle images separately
    content
    |> Enum.filter(fn
      %{type: "text"} -> true
      %{"type" => "text"} -> true
      _ -> false
    end)
    |> Enum.map(fn
      %{type: "text", text: text} -> text
      %{"type" => "text", "text" => text} -> text
      _ -> ""
    end)
    |> Enum.join(" ")
  end

  defp format_content(content), do: to_string(content)

  defp maybe_add_images(message_map, %{content: content}) when is_list(content) do
    images =
      content
      |> Enum.filter(fn
        %{type: "image"} -> true
        %{type: "image_url"} -> true
        %{"type" => "image"} -> true
        %{"type" => "image_url"} -> true
        _ -> false
      end)
      |> Enum.map(&extract_image_data/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(images) do
      message_map
    else
      Map.put(message_map, "images", images)
    end
  end

  defp maybe_add_images(message_map, _), do: message_map

  defp extract_image_data(%{type: "image", data: data}) when is_binary(data) do
    data
  end

  defp extract_image_data(%{type: "image_url", image_url: %{url: url}}) do
    case parse_data_url(url) do
      {:ok, _media_type, data} -> data
      :error -> nil
    end
  end

  defp extract_image_data(%{"type" => "image", "data" => data}) when is_binary(data) do
    data
  end

  defp extract_image_data(%{"type" => "image_url", "image_url" => %{"url" => url}}) do
    case parse_data_url(url) do
      {:ok, _media_type, data} -> data
      :error -> nil
    end
  end

  defp extract_image_data(_), do: nil

  defp maybe_add_options(body, config) do
    options =
      %{}
      |> maybe_put_option(:temperature, config[:temperature])
      |> maybe_put_option(:top_p, config[:top_p])
      |> maybe_put_option(:top_k, config[:top_k])
      |> maybe_put_option(:seed, config[:seed])
      |> maybe_put_option(:num_predict, config[:max_tokens])
      |> maybe_put_option(:stop, config[:stop])

    if map_size(options) > 0 do
      Map.put(body, :options, options)
    else
      body
    end
  end

  defp maybe_put_option(map, _key, nil), do: map
  defp maybe_put_option(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_format(body, %{format: format}) when format in ["json", :json] do
    Map.put(body, :format, "json")
  end

  defp maybe_add_format(body, _), do: body

  defp maybe_add_keep_alive(body, %{keep_alive: keep_alive}) do
    Map.put(body, :keep_alive, keep_alive)
  end

  defp maybe_add_keep_alive(body, _), do: body

  defp parse_data_url("data:" <> rest) do
    case String.split(rest, ";base64,", parts: 2) do
      [media_type, data] -> {:ok, media_type, data}
      _ -> :error
    end
  end

  defp parse_data_url(_), do: :error

  defp compact(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
