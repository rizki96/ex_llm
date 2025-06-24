defmodule ExLLM.Plugs.AWSAuth do
  @moduledoc """
  AWS Authentication plug that handles SigV4 request signing for AWS services.

  This plug provides AWS SigV4 authentication for services like Bedrock. It supports
  multiple credential sources following AWS credential precedence:

  1. Explicit credentials in configuration
  2. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)
  3. AWS profiles from ~/.aws/credentials
  4. EC2 instance metadata service
  5. ECS task role credentials

  ## Expected Assigns

  - `:aws_service` - AWS service name (e.g., "bedrock-runtime")
  - `:aws_region` - AWS region (defaults to "us-east-1")
  - `:http_method` - HTTP method for the request
  - `:url` - Full URL for the request
  - `:headers` - HTTP headers map
  - `:body` - Request body (string)

  ## Sets in Assigns

  - `:signed_headers` - Headers with AWS authentication signature
  - `:aws_credentials` - Resolved AWS credentials for debugging
  """

  use ExLLM.Plug
  alias ExLLM.Pipeline.Request

  @impl true
  def call(%Request{state: :executing} = request, _opts) do
    aws_service = request.assigns[:aws_service]
    aws_region = request.assigns[:aws_region] || get_default_region()

    if aws_service do
      sign_aws_request(request, aws_service, aws_region)
    else
      # Not an AWS request, pass through
      request
    end
  end

  def call(request, _opts), do: request

  defp sign_aws_request(request, service, region) do
    case get_aws_credentials(request) do
      {:ok, credentials} ->
        signed_headers = create_signed_headers(request, credentials, service, region)

        request
        |> Request.assign(:signed_headers, signed_headers)
        |> Request.assign(:aws_credentials, sanitize_credentials(credentials))

      {:error, reason} ->
        request
        |> Request.add_error(%{
          plug: __MODULE__,
          reason: reason,
          message: "AWS authentication failed: #{inspect(reason)}"
        })
        |> Request.put_state(:error)
        |> Request.halt()
    end
  end

  defp create_signed_headers(request, credentials, service, region) do
    method = request.assigns[:http_method] || "POST"
    url = request.assigns[:url] || ""
    headers = request.assigns[:headers] || %{}
    body = request.assigns[:body] || ""

    # Parse URL to get host and path
    uri = URI.parse(url)
    host = uri.host || ""
    path = uri.path || "/"
    query = uri.query || ""

    # Create canonical request
    timestamp = get_timestamp()
    date = get_date(timestamp)

    # Add required AWS headers
    aws_headers =
      headers
      |> Map.put("host", host)
      |> Map.put("x-amz-date", timestamp)
      |> maybe_add_session_token(credentials)
      |> maybe_add_content_type()

    # Create signature
    signature_components = %{
      method: method,
      path: path,
      query: query,
      headers: aws_headers,
      body: body,
      service: service,
      region: region,
      access_key: credentials.access_key_id,
      secret_key: credentials.secret_access_key,
      session_token: credentials.session_token,
      timestamp: timestamp,
      date: date
    }

    signature = create_signature_v4(signature_components)
    authorization_header = build_authorization_header(signature_components, signature)

    Map.put(aws_headers, "authorization", authorization_header)
  end

  defp get_aws_credentials(request) do
    # Check for credentials in request options first
    case request.options[:aws_credentials] do
      nil ->
        # Fall back to standard AWS credential resolution
        resolve_aws_credentials(request.options)

      credentials when is_map(credentials) ->
        {:ok, credentials}
    end
  end

  defp resolve_aws_credentials(options) do
    cond do
      # 1. Explicit credentials in options
      options[:aws_access_key_id] && options[:aws_secret_access_key] ->
        {:ok,
         %{
           access_key_id: options[:aws_access_key_id],
           secret_access_key: options[:aws_secret_access_key],
           session_token: options[:aws_session_token]
         }}

      # 2. Environment variables
      System.get_env("AWS_ACCESS_KEY_ID") && System.get_env("AWS_SECRET_ACCESS_KEY") ->
        {:ok,
         %{
           access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
           secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
           session_token: System.get_env("AWS_SESSION_TOKEN")
         }}

      # 3. AWS Profile
      profile = options[:aws_profile] || System.get_env("AWS_PROFILE") ->
        load_profile_credentials(profile)

      # 4. Try instance metadata
      true ->
        load_instance_credentials()
    end
  end

  defp load_profile_credentials(profile) do
    credentials_path = Path.expand("~/.aws/credentials")

    if File.exists?(credentials_path) do
      case File.read(credentials_path) do
        {:ok, content} ->
          parse_aws_credentials_file(content, profile)

        {:error, _} ->
          {:error, "Failed to read AWS credentials file"}
      end
    else
      {:error, "AWS credentials file not found"}
    end
  end

  defp parse_aws_credentials_file(content, profile) do
    lines = String.split(content, "\n")
    profile_section = "[#{profile}]"

    case find_profile_section(lines, profile_section) do
      {:ok, section_lines} ->
        access_key = find_credential(section_lines, "aws_access_key_id")
        secret_key = find_credential(section_lines, "aws_secret_access_key")
        session_token = find_credential(section_lines, "aws_session_token")

        if access_key && secret_key do
          {:ok,
           %{
             access_key_id: access_key,
             secret_access_key: secret_key,
             session_token: session_token
           }}
        else
          {:error, "Incomplete credentials for profile #{profile}"}
        end

      :error ->
        {:error, "Profile #{profile} not found"}
    end
  end

  defp find_profile_section(lines, profile_header) do
    case Enum.find_index(lines, &(&1 == profile_header)) do
      nil ->
        :error

      index ->
        section_lines =
          lines
          |> Enum.drop(index + 1)
          |> Enum.take_while(&(!String.starts_with?(&1, "[")))

        {:ok, section_lines}
    end
  end

  defp find_credential(lines, key) do
    lines
    |> Enum.find_value(fn line ->
      case String.split(line, "=", parts: 2) do
        [k, v] ->
          if String.trim(k) == key do
            String.trim(v)
          else
            nil
          end

        _ ->
          nil
      end
    end)
  end

  defp load_instance_credentials do
    # Try EC2 instance metadata service
    metadata_url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"

    case make_http_request(metadata_url, [], 1_000) do
      {:ok, %{status: 200, body: role_name}} ->
        creds_url = metadata_url <> String.trim(role_name)

        case make_http_request(creds_url, [], 5_000) do
          {:ok, %{status: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, creds} ->
                {:ok,
                 %{
                   access_key_id: creds["AccessKeyId"],
                   secret_access_key: creds["SecretAccessKey"],
                   session_token: creds["Token"]
                 }}

              {:error, _} ->
                {:error, "Failed to parse instance credentials"}
            end

          _ ->
            load_ecs_task_credentials()
        end

      _ ->
        load_ecs_task_credentials()
    end
  end

  defp load_ecs_task_credentials do
    # Check for ECS task role
    relative_uri = System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

    if relative_uri do
      url = "http://169.254.170.2" <> relative_uri

      case make_http_request(url, [], 5_000) do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, creds} ->
              {:ok,
               %{
                 access_key_id: creds["AccessKeyId"],
                 secret_access_key: creds["SecretAccessKey"],
                 session_token: creds["Token"]
               }}

            {:error, _} ->
              {:error, "Failed to parse ECS task credentials"}
          end

        _ ->
          {:error, "Failed to retrieve ECS task credentials"}
      end
    else
      {:error, "No AWS credentials found"}
    end
  end

  # Simple HTTP request for credential fetching
  defp make_http_request(url, headers, timeout) do
    try do
      case Req.get(url, headers: headers, receive_timeout: timeout) do
        {:ok, response} ->
          {:ok, %{status: response.status, body: response.body}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      _ ->
        {:error, "HTTP request failed"}
    end
  end

  # SigV4 Signature Implementation

  defp create_signature_v4(components) do
    canonical_request = create_canonical_request(components)
    string_to_sign = create_string_to_sign(canonical_request, components)
    signing_key = create_signing_key(components)

    :crypto.mac(:hmac, :sha256, signing_key, string_to_sign)
    |> Base.encode16(case: :lower)
  end

  defp create_canonical_request(%{
         method: method,
         path: path,
         query: query,
         headers: headers,
         body: body
       }) do
    canonical_headers =
      headers
      |> Enum.sort_by(fn {k, _v} -> String.downcase(k) end)
      |> Enum.map(fn {k, v} -> "#{String.downcase(k)}:#{String.trim(v)}" end)
      |> Enum.join("\n")

    signed_headers =
      headers
      |> Enum.map(fn {k, _v} -> String.downcase(k) end)
      |> Enum.sort()
      |> Enum.join(";")

    body_hash = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    [
      String.upcase(method),
      path,
      query || "",
      canonical_headers,
      "",
      signed_headers,
      body_hash
    ]
    |> Enum.join("\n")
  end

  defp create_string_to_sign(canonical_request, %{
         timestamp: timestamp,
         region: region,
         service: service
       }) do
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = "#{get_date(timestamp)}/#{region}/#{service}/aws4_request"

    hashed_canonical_request =
      :crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower)

    [
      algorithm,
      timestamp,
      credential_scope,
      hashed_canonical_request
    ]
    |> Enum.join("\n")
  end

  defp create_signing_key(%{secret_key: secret_key, date: date, region: region, service: service}) do
    k_date = :crypto.mac(:hmac, :sha256, "AWS4" <> secret_key, date)
    k_region = :crypto.mac(:hmac, :sha256, k_date, region)
    k_service = :crypto.mac(:hmac, :sha256, k_region, service)
    :crypto.mac(:hmac, :sha256, k_service, "aws4_request")
  end

  defp build_authorization_header(
         %{
           access_key: access_key,
           date: date,
           region: region,
           service: service,
           headers: headers
         },
         signature
       ) do
    credential = "#{access_key}/#{date}/#{region}/#{service}/aws4_request"

    signed_headers =
      headers
      |> Enum.map(fn {k, _v} -> String.downcase(k) end)
      |> Enum.sort()
      |> Enum.join(";")

    "AWS4-HMAC-SHA256 Credential=#{credential}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
  end

  # Utility functions

  defp get_timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:basic)
    |> String.replace("Z", "")
  end

  defp get_date(timestamp) do
    String.slice(timestamp, 0, 8)
  end

  defp get_default_region do
    System.get_env("AWS_REGION") || System.get_env("AWS_DEFAULT_REGION") || "us-east-1"
  end

  defp maybe_add_session_token(headers, %{session_token: token}) when is_binary(token) do
    Map.put(headers, "x-amz-security-token", token)
  end

  defp maybe_add_session_token(headers, _), do: headers

  defp maybe_add_content_type(headers) do
    if Map.has_key?(headers, "content-type") do
      headers
    else
      Map.put(headers, "content-type", "application/x-amz-json-1.1")
    end
  end

  defp sanitize_credentials(%{access_key_id: access_key} = credentials) do
    # Only show first 4 characters for debugging
    safe_access_key = String.slice(access_key, 0, 4) <> "****"
    %{credentials | access_key_id: safe_access_key, secret_access_key: "****"}
  end
end
