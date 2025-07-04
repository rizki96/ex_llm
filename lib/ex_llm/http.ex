defmodule ExLLM.HTTP do
  @moduledoc """
  Type-safe wrapper around Tesla responses.

  This module provides a clean interface for handling Tesla.Env responses
  while avoiding dialyzer warnings about the polymorphic body field.
  It also decouples the rest of the codebase from Tesla internals.
  """

  @type ok_response(body_type) :: %Tesla.Env{status: 200..299, body: body_type}
  @type error_response :: %Tesla.Env{status: 300..599}
  @type streaming_response :: %Tesla.Env{body: reference()}

  @doc """
  Check if a response was successful (2xx status code).
  """
  @spec successful?(Tesla.Env.t()) :: boolean()
  def successful?(%Tesla.Env{status: status}), do: status in 200..299

  @doc """
  Extract the body from a Tesla.Env response.
  """
  @spec get_body(Tesla.Env.t()) :: term()
  def get_body(%Tesla.Env{body: body}), do: body

  @doc """
  Extract the status code from a Tesla.Env response.
  """
  @spec get_status(Tesla.Env.t()) :: integer()
  def get_status(%Tesla.Env{status: status}), do: status

  @doc """
  Extract headers from a Tesla.Env response.
  """
  @spec get_headers(Tesla.Env.t()) :: [{binary(), binary()}]
  def get_headers(%Tesla.Env{headers: headers}), do: headers

  @doc """
  Handle a response, returning {:ok, body} for success or {:error, env} for errors.
  """
  @spec handle_response(Tesla.Env.t()) :: {:ok, term()} | {:error, Tesla.Env.t()}
  def handle_response(%Tesla.Env{status: status} = env) when status in 200..299 do
    {:ok, get_body(env)}
  end

  def handle_response(%Tesla.Env{} = env) do
    {:error, env}
  end

  @doc """
  Check if the response body is a streaming reference.
  """
  @spec streaming?(Tesla.Env.t()) :: boolean()
  def streaming?(%Tesla.Env{body: body}), do: is_reference(body)

  @doc """
  Check if the response indicates a timeout error.
  """
  @spec timeout_error?(Tesla.Env.t()) :: boolean()
  def timeout_error?(%Tesla.Env{body: {:error, :req_timedout}}), do: true
  def timeout_error?(_), do: false

  @doc """
  Extract error information from a non-successful response.
  """
  @spec get_error_info(Tesla.Env.t()) :: {integer(), term()}
  def get_error_info(%Tesla.Env{status: status, body: body}) do
    {status, body}
  end

  @doc """
  Parse response based on status code, with specific handling for different status ranges.
  """
  @spec parse_response(Tesla.Env.t(), (term() -> term())) :: {:ok, term()} | {:error, term()}
  def parse_response(%Tesla.Env{status: status} = env, parser) when status in 200..299 do
    body = get_body(env)
    {:ok, parser.(body)}
  end

  def parse_response(%Tesla.Env{status: status, body: body}, _parser) do
    {:error, {:api_error, %{status: status, body: body}}}
  end

  def parse_response({:error, reason}, _parser) do
    {:error, reason}
  end
end
