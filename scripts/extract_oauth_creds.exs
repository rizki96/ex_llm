#!/usr/bin/env elixir

# Extract OAuth2 Credentials from Google's JSON file
#
# Usage: elixir scripts/extract_oauth_creds.exs path/to/client_secret.json

Mix.install([{:jason, "~> 1.4"}])

defmodule ExtractCreds do
  def run(args) do
    case args do
      [json_file] ->
        extract_credentials(json_file)
      _ ->
        IO.puts("Usage: elixir scripts/extract_oauth_creds.exs path/to/client_secret.json")
        IO.puts("\nDownload this file from Google Cloud Console > APIs & Services > Credentials")
        System.halt(1)
    end
  end

  defp extract_credentials(json_file) do
    case File.read(json_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            display_credentials(data)
          {:error, _} ->
            IO.puts("❌ Error: Invalid JSON in file")
            System.halt(1)
        end
      {:error, :enoent} ->
        IO.puts("❌ Error: File not found: #{json_file}")
        System.halt(1)
      {:error, reason} ->
        IO.puts("❌ Error reading file: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp display_credentials(data) do
    # Handle different OAuth2 client types
    creds = case data do
      %{"installed" => installed} -> installed
      %{"web" => web} -> web
      _ -> 
        IO.puts("❌ Error: Unrecognized credential format")
        IO.puts("Expected 'installed' or 'web' application type")
        System.halt(1)
    end

    client_id = creds["client_id"]
    client_secret = creds["client_secret"]
    
    if client_id && client_secret do
      IO.puts("\n✅ OAuth2 Credentials Found!\n")
      IO.puts("Add these to your environment:\n")
      IO.puts("export GOOGLE_CLIENT_ID=\"#{client_id}\"")
      IO.puts("export GOOGLE_CLIENT_SECRET=\"#{client_secret}\"\n")
      
      IO.puts("Or add to your shell profile (e.g., ~/.bashrc or ~/.zshrc):\n")
      IO.puts("echo 'export GOOGLE_CLIENT_ID=\"#{client_id}\"' >> ~/.bashrc")
      IO.puts("echo 'export GOOGLE_CLIENT_SECRET=\"#{client_secret}\"' >> ~/.bashrc\n")
      
      IO.puts("Then run:")
      IO.puts("source ~/.bashrc  # or restart your terminal\n")
      
      IO.puts("Finally, run the OAuth2 setup:")
      IO.puts("elixir scripts/setup_oauth2.exs")
    else
      IO.puts("❌ Error: Could not find client_id and client_secret in the JSON file")
      System.halt(1)
    end
  end
end

# Run with command line arguments
ExtractCreds.run(System.argv())