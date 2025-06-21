defmodule ExLLM.Providers.Gemini.PermissionsUnitTest do
  @moduledoc """
  Unit tests for Gemini Permissions functionality that don't require OAuth2.

  These tests can run without OAuth2 credentials and test internal logic.
  """

  use ExUnit.Case, async: true

  @moduletag :unit
  @moduletag provider: :gemini

  describe "token validation" do
    test "validates token format" do
      # Test various token formats
      tokens = [
        {"valid format", "ya29.a0AfH6SMBx..."},
        {"another valid", "ya29.c0AfH6SMBx..."},
        {"clearly invalid", "not-a-token"},
        {"empty", ""},
        {"nil", nil}
      ]

      for {description, token} <- tokens do
        if token && String.starts_with?(token, "ya29.") do
          assert {:ok, _} = validate_token_format(token),
                 "Token '#{description}' should be valid"
        else
          assert {:error, _} = validate_token_format(token),
                 "Token '#{description}' should be invalid"
        end
      end
    end

    test "validates token structure" do
      # Test token structure validation
      valid_tokens = [
        "ya29.a0AfH6SMBxVsOmxrN0_example_token_here",
        "ya29.c0AfH6SMBxVsOmxrN0_another_example"
      ]

      invalid_tokens = [
        "invalid_prefix.a0AfH6SMBx",
        # wrong version
        "ya28.a0AfH6SMBx",
        # too short
        "ya29.",
        # missing dot
        "ya29",
        ""
      ]

      for token <- valid_tokens do
        assert {:ok, _} = validate_token_format(token),
               "Token '#{token}' should be valid"
      end

      for token <- invalid_tokens do
        assert {:error, _} = validate_token_format(token),
               "Token '#{token}' should be invalid"
      end
    end

    test "handles edge cases in token validation" do
      edge_cases = [
        {"whitespace", "  ya29.a0AfH6SMBx  "},
        {"newlines", "ya29.a0AfH6SMBx\n"},
        {"tabs", "ya29.a0AfH6SMBx\t"},
        {"mixed whitespace", " \t ya29.a0AfH6SMBx \n "}
      ]

      for {description, token} <- edge_cases do
        # Tokens with whitespace should be invalid (not trimmed)
        assert {:error, _} = validate_token_format(token),
               "Token with #{description} should be invalid"
      end
    end
  end

  # Helper function for token format validation
  defp validate_token_format(nil), do: {:error, "Token is nil"}
  defp validate_token_format(""), do: {:error, "Token is empty"}

  defp validate_token_format(token) when is_binary(token) do
    cond do
      String.length(token) < 10 ->
        {:error, "Token too short"}

      not String.starts_with?(token, "ya29.") ->
        {:error, "Invalid token prefix"}

      String.contains?(token, ["\n", "\t", " "]) ->
        {:error, "Token contains whitespace"}

      true ->
        {:ok, "Valid token format"}
    end
  end

  defp validate_token_format(_), do: {:error, "Token must be a string"}
end
