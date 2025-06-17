#!/usr/bin/env elixir

# Cleanup OAuth2 Test Data
#
# This script removes test corpora to free up quota for new tests
# Usage: elixir scripts/cleanup_oauth2_test_data.exs

Mix.install([
  {:ex_llm, path: "."},
  {:req, "~> 0.5.0"},
  {:jason, "~> 1.4"}
])

defmodule CleanupTestData do
  alias ExLLM.Providers.Gemini.Corpus
  
  def run do
    IO.puts("\n🧹 OAuth2 Test Data Cleanup")
    IO.puts("=" <> String.duplicate("=", 40))
    
    case get_token() do
      {:ok, token} ->
        cleanup_corpora(token)
      {:error, reason} ->
        IO.puts("\n❌ Error: #{reason}")
        System.halt(1)
    end
  end
  
  defp get_token do
    case File.read(".gemini_tokens") do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, tokens} -> 
            {:ok, tokens["access_token"]}
          {:error, _} -> 
            {:error, "Invalid token file format"}
        end
      {:error, :enoent} ->
        {:error, "No OAuth2 tokens found! Run: elixir scripts/setup_oauth2.exs"}
      {:error, reason} ->
        {:error, "Failed to read tokens: #{reason}"}
    end
  end
  
  defp cleanup_corpora(token) do
    IO.puts("\n📋 Listing existing corpora...")
    
    case Corpus.list_corpora([], oauth_token: token) do
      {:ok, response} ->
        corpora = response.corpora
        IO.puts("   Found #{length(corpora)} corpora")
        
        # Filter test corpora
        test_corpora = Enum.filter(corpora, fn corpus ->
          display_name = corpus.display_name || ""
          String.contains?(String.downcase(display_name), "test") ||
          String.contains?(String.downcase(display_name), "qa-") ||
          String.contains?(String.downcase(display_name), "doc-") ||
          String.contains?(String.downcase(display_name), "chunk-")
        end)
        
        if length(test_corpora) == 0 do
          IO.puts("\n✅ No test corpora found to cleanup")
          
          if length(corpora) >= 5 do
            IO.puts("\n⚠️  Warning: You have #{length(corpora)} corpora (quota limit is 5)")
            IO.puts("   Non-test corpora:")
            Enum.each(corpora, fn corpus ->
              IO.puts("   - #{corpus.name}: #{corpus.display_name}")
            end)
          end
        else
          IO.puts("\n🗑️  Found #{length(test_corpora)} test corpora to delete:")
          Enum.each(test_corpora, fn corpus ->
            IO.puts("   - #{corpus.name}: #{corpus.display_name}")
          end)
          
          # Check for --force flag
          force = "--force" in System.argv()
          
          if force do
            IO.puts("\n🚀 Force mode enabled - proceeding with deletion")
            delete_corpora(test_corpora, token)
          else
            IO.write("\nProceed with deletion? [y/N]: ")
            
            case IO.gets("") do
              :eof ->
                IO.puts("\n❌ No input available - use --force flag to proceed")
              input ->
                case String.trim(input) |> String.downcase() do
                  "y" ->
                    delete_corpora(test_corpora, token)
                  _ ->
                    IO.puts("\n❌ Cleanup cancelled")
                end
            end
          end
        end
        
      {:error, error} ->
        IO.puts("\n❌ Error listing corpora: #{inspect(error)}")
        System.halt(1)
    end
  end
  
  defp delete_corpora(corpora, token) do
    IO.puts("\n🗑️  Deleting corpora...")
    
    results = Enum.map(corpora, fn corpus ->
      IO.write("   Deleting #{corpus.name}... ")
      
      case Corpus.delete_corpus(corpus.name, oauth_token: token, force: true) do
        :ok ->
          IO.puts("✅")
          {:ok, corpus.name}
        {:error, error} ->
          IO.puts("❌")
          IO.puts("     Error: #{inspect(error)}")
          {:error, corpus.name, error}
      end
    end)
    
    successful = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    failed = Enum.count(results, fn r -> match?({:error, _, _}, r) end)
    
    IO.puts("\n📊 Summary:")
    IO.puts("   ✅ Successfully deleted: #{successful}")
    IO.puts("   ❌ Failed to delete: #{failed}")
    
    # List remaining corpora
    case Corpus.list_corpora([], oauth_token: token) do
      {:ok, response} ->
        IO.puts("\n📋 Remaining corpora: #{length(response.corpora)}/5")
      _ ->
        :ok
    end
  end
end

# Run the cleanup
CleanupTestData.run()