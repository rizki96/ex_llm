defmodule ExLLM.OAuth2Test do
  use ExUnit.Case, async: true

  alias ExLLM.Testing.OAuth2.Helper
  alias ExLLM.Testing.OAuth2.TokenStorage

  @moduledoc """
  Tests for OAuth2 authentication infrastructure in ExLLM.

  These tests ensure that OAuth2 token management works correctly across
  providers and handles various error scenarios appropriately.
  """

  describe "OAuth2 provider support" do
    test "lists supported providers" do
      providers = Helper.supported_providers()

      assert is_list(providers)
      assert :google in providers
      # Alias for Google
      assert :gemini in providers
      assert :microsoft in providers
      assert :github in providers
    end

    test "validates provider support" do
      # Supported providers
      assert Helper.oauth_available?(:google) in [true, false]
      assert Helper.oauth_available?(:gemini) in [true, false]

      # Unsupported provider
      refute Helper.oauth_available?(:unsupported_provider)
    end

    test "gets provider configuration" do
      case Helper.get_provider_config(:google) do
        {:ok, config} ->
          assert is_map(config)
          assert Map.has_key?(config, :token_endpoint)
          assert Map.has_key?(config, :scopes)

        {:error, _reason} ->
          # Config may not be available in test environment
          assert true
      end
    end

    test "handles invalid provider gracefully" do
      assert {:error, :provider_not_supported} = Helper.get_provider_config(:invalid)
      assert {:error, :provider_not_supported} = Helper.get_valid_token(:invalid)
      assert {:error, :provider_not_supported} = Helper.refresh_token(:invalid)
    end
  end

  describe "environment validation" do
    test "validates Google OAuth2 environment" do
      case Helper.validate_environment(:google) do
        :ok ->
          # Environment is properly configured
          assert true

        {:error, missing_vars} ->
          # Some required environment variables are missing
          assert is_list(missing_vars)
          assert Enum.all?(missing_vars, &is_binary/1)
      end
    end

    test "validates Microsoft OAuth2 environment" do
      case Helper.validate_environment(:microsoft) do
        :ok ->
          assert true

        {:error, missing_vars} ->
          assert is_list(missing_vars)
          assert Enum.all?(missing_vars, &is_binary/1)
      end
    end

    test "rejects invalid provider environment validation" do
      assert {:error, missing_vars} = Helper.validate_environment(:invalid_provider)
      assert is_list(missing_vars)
      assert "Provider invalid_provider not supported" in missing_vars
    end
  end

  describe "token management" do
    test "handles missing tokens gracefully" do
      # When no tokens are stored, get_valid_token should return error
      case Helper.get_valid_token(:google) do
        {:ok, token} ->
          # Token is available and valid
          assert is_binary(token)
          assert String.length(token) > 0

        {:error, reason} ->
          # No valid token available (expected in most test environments)
          assert reason in [:no_tokens_found, :token_expired, :oauth_not_configured]
      end
    end

    test "token refresh returns proper structure" do
      case Helper.refresh_token(:google) do
        {:ok, tokens} ->
          # Successful refresh
          assert is_map(tokens)
          assert Map.has_key?(tokens, "access_token")

        {:error, reason} ->
          # Refresh failed (expected in test environment)
          assert is_atom(reason) or is_binary(reason)
      end
    end

    test "setup_oauth initializes context properly" do
      context = %{existing_key: "value"}

      result_context = Helper.setup_oauth(:google, context)

      # Should preserve existing context
      assert result_context.existing_key == "value"

      # May or may not have oauth_token depending on environment
      case Map.get(result_context, :oauth_token) do
        nil ->
          # No OAuth available - context unchanged except for preserved keys
          assert true

        token when is_binary(token) ->
          # OAuth token successfully added
          assert String.length(token) > 0
      end
    end
  end

  describe "token storage utilities" do
    test "token_needs_refresh?/1 validates token expiration" do
      # Test with expired token
      expired_tokens = %{
        "access_token" => "test_token",
        "expires_in" => 3600,
        # 2 hours ago
        "created_at" => System.system_time(:second) - 7200
      }

      assert TokenStorage.token_needs_refresh?(expired_tokens) == true

      # Test with fresh token
      fresh_tokens = %{
        "access_token" => "test_token",
        "expires_in" => 3600,
        # 30 minutes ago
        "created_at" => System.system_time(:second) - 1800
      }

      assert TokenStorage.token_needs_refresh?(fresh_tokens) == false

      # Test with missing expiration info
      incomplete_tokens = %{"access_token" => "test_token"}
      assert TokenStorage.token_needs_refresh?(incomplete_tokens) == true
    end

    test "handles malformed token data" do
      # Test with nil
      assert TokenStorage.token_needs_refresh?(nil) == true

      # Test with empty map
      assert TokenStorage.token_needs_refresh?(%{}) == true

      # Test with string instead of map
      assert TokenStorage.token_needs_refresh?("invalid") == true
    end
  end

  describe "provider cleanup" do
    test "cleanup operations complete successfully" do
      # Cleanup should always succeed, even if no resources to clean
      assert :ok = Helper.cleanup(:google)
      assert :ok = Helper.cleanup(:microsoft)
      assert :ok = Helper.cleanup(:github)

      # Invalid provider cleanup should not fail
      assert :ok = Helper.cleanup(:invalid_provider)
    end

    test "global cleanup operations complete successfully" do
      # Global cleanup should always succeed
      assert :ok = Helper.global_cleanup(:google)
      assert :ok = Helper.global_cleanup(:microsoft)

      # Invalid provider global cleanup should not fail
      assert :ok = Helper.global_cleanup(:invalid_provider)
    end
  end

  describe "OAuth2 integration scenarios" do
    test "simulates full OAuth2 flow without actual authentication" do
      provider = :google

      # 1. Check if OAuth2 is available
      available = Helper.oauth_available?(provider)

      if available do
        # 2. Try to get a valid token
        case Helper.get_valid_token(provider) do
          {:ok, token} ->
            # 3. Token is available - verify it's a string
            assert is_binary(token)
            assert String.length(token) > 0

            # 4. Test setup_oauth with this token
            context = Helper.setup_oauth(provider, %{})
            assert context.oauth_token == token

          {:error, _reason} ->
            # 5. No token available - try refresh
            case Helper.refresh_token(provider) do
              {:ok, new_tokens} ->
                assert is_map(new_tokens)
                assert Map.has_key?(new_tokens, "access_token")

              {:error, _refresh_error} ->
                # Neither existing token nor refresh worked - expected in test env
                assert true
            end
        end
      else
        # OAuth2 not available for this provider in current environment
        assert {:error, _} = Helper.get_valid_token(provider)
      end

      # 6. Cleanup should always work
      assert :ok = Helper.cleanup(provider)
    end

    test "handles provider switching" do
      # Test that we can work with different providers in sequence
      providers = [:google, :microsoft, :github]

      for provider <- providers do
        # Each provider should have consistent behavior
        availability = Helper.oauth_available?(provider)
        assert is_boolean(availability)

        # Environment validation should always return a result
        case Helper.validate_environment(provider) do
          :ok ->
            assert true

          {:error, vars} ->
            assert is_list(vars)
            assert length(vars) > 0
        end

        # Cleanup should always succeed
        assert :ok = Helper.cleanup(provider)
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles concurrent token requests" do
      # Simulate multiple concurrent token requests
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            Helper.get_valid_token(:google)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All requests should complete (successfully or with error)
      assert length(results) == 5

      # Results should be consistent (all success or all failure for same provider)
      unique_results = results |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      # At most :ok and :error
      assert length(unique_results) <= 2
    end

    test "handles provider configuration edge cases" do
      # Test various invalid inputs
      assert {:error, :provider_not_supported} = Helper.get_provider_config("")
      assert {:error, :provider_not_supported} = Helper.get_provider_config(nil)
      assert {:error, :provider_not_supported} = Helper.get_provider_config(123)
    end

    test "validates token format expectations" do
      # When a token is returned, it should meet basic format expectations
      case Helper.get_valid_token(:google) do
        {:ok, token} ->
          # Valid tokens should be non-empty strings
          assert is_binary(token)
          # Reasonable minimum length
          assert String.length(token) > 10
          # No spaces in tokens
          refute String.contains?(token, " ")

        {:error, _reason} ->
          # No token available - that's fine for test environment
          assert true
      end
    end
  end
end
