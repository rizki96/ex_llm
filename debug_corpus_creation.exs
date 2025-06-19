#!/usr/bin/env elixir

Mix.install([{:req, "~> 0.5"}, {:jason, "~> 1.4"}])

Code.require_file("lib/ex_llm/providers/gemini/corpus.ex")
Code.require_file("lib/ex_llm/providers/gemini/base.ex")
Code.require_file("lib/ex_llm/testing/gemini_oauth2_helper.ex")

alias ExLLM.Providers.Gemini.Corpus
alias ExLLM.Testing.GeminiOAuth2Helper

case GeminiOAuth2Helper.get_valid_token() do
  {:ok, token} ->
    IO.puts("Token: #{String.slice(token, 0, 20)}...")
    
    # Try to create a corpus and see what happens
    corpus_name = "debug-test-corpus"
    
    IO.puts("Creating corpus with display_name: #{corpus_name}")
    
    case Corpus.create_corpus(%{display_name: corpus_name}, oauth_token: token) do
      {:ok, corpus} ->
        IO.puts("SUCCESS!")
        IO.puts("Corpus struct: #{inspect(corpus)}")
        IO.puts("Name field: #{inspect(corpus.name)}")
        IO.puts("Display name field: #{inspect(corpus.display_name)}")
        
        # Clean up
        if corpus.name do
          Corpus.delete_corpus(corpus.name, oauth_token: token)
          IO.puts("Cleaned up corpus")
        end
        
      {:error, error} ->
        IO.puts("ERROR: #{inspect(error)}")
    end
    
  {:error, reason} ->
    IO.puts("No OAuth token available: #{reason}")
end