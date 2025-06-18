#!/usr/bin/env elixir

# Test AWS Bedrock integration
Mix.install([
  {:ex_llm, path: "."}
])

defmodule BedrockTest do
  require Logger

  def test_bedrock_pipeline() do
    IO.puts("\n============================================================")
    IO.puts("Testing AWS Bedrock pipeline configuration")
    IO.puts("============================================================")
    
    # Test different model formats
    models = [
      "anthropic.claude-v2",
      "anthropic.claude-3-sonnet-20240229-v1:0",
      "amazon.titan-text-express-v1",
      "meta.llama2-13b-chat-v1",
      "cohere.command-text-v14",
      "mistral.mistral-7b-instruct-v0:2"
    ]
    
    Enum.each(models, fn model ->
      IO.puts("\nTesting model: #{model}")
      
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Hello"}
      ]
      
      # Test chat pipeline
      try do
        request = ExLLM.Pipeline.Request.new(:bedrock, messages, %{model: model})
        pipeline = ExLLM.Providers.get_pipeline(:bedrock, :chat)
        
        IO.puts("  ✅ Chat pipeline configured")
        IO.puts("  Pipeline: #{inspect(pipeline |> Enum.map(fn 
          {mod, _opts} -> mod
          mod -> mod
        end))}")
      rescue
        e -> IO.puts("  ❌ Chat pipeline error: #{Exception.message(e)}")
      end
      
      # Test streaming pipeline
      try do
        request = ExLLM.Pipeline.Request.new(:bedrock, messages, %{model: model, stream: true})
        pipeline = ExLLM.Providers.get_pipeline(:bedrock, :stream)
        
        IO.puts("  ✅ Stream pipeline configured")
      rescue
        e -> IO.puts("  ❌ Stream pipeline error: #{Exception.message(e)}")
      end
    end)
  end

  def test_bedrock_with_credentials() do
    IO.puts("\n\n============================================================")
    IO.puts("Testing AWS Bedrock with credentials (if available)")
    IO.puts("============================================================")
    
    # Check if AWS credentials are available
    aws_access_key = System.get_env("AWS_ACCESS_KEY_ID")
    aws_secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")
    aws_region = System.get_env("AWS_REGION") || "us-east-1"
    
    if aws_access_key && aws_secret_key do
      IO.puts("AWS credentials found. Testing with real API...")
      
      messages = [
        %{role: "user", content: "Say hello in 5 words"}
      ]
      
      try do
        # Test regular chat
        result = ExLLM.ChatBuilder.new(:bedrock, messages)
          |> ExLLM.ChatBuilder.with_model("anthropic.claude-v2")
          |> ExLLM.ChatBuilder.with_options(%{
            aws_access_key_id: aws_access_key,
            aws_secret_access_key: aws_secret_key,
            aws_region: aws_region
          })
          |> ExLLM.ChatBuilder.execute()
          
        case result do
          {:ok, response} ->
            IO.puts("✅ Bedrock chat successful")
            IO.puts("Response: #{inspect(response.content)}")
          {:error, reason} ->
            IO.puts("❌ Bedrock chat failed: #{inspect(reason)}")
        end
      rescue
        e ->
          IO.puts("💥 Bedrock chat crashed: #{Exception.message(e)}")
      end
      
      # Test streaming
      IO.puts("\nTesting streaming...")
      callback = fn chunk ->
        IO.write(".")
      end
      
      try do
        result = ExLLM.ChatBuilder.new(:bedrock, messages)
          |> ExLLM.ChatBuilder.with_model("anthropic.claude-v2")
          |> ExLLM.ChatBuilder.with_options(%{
            aws_access_key_id: aws_access_key,
            aws_secret_access_key: aws_secret_key,
            aws_region: aws_region
          })
          |> ExLLM.ChatBuilder.stream(callback)
          
        case result do
          :ok ->
            IO.puts("\n✅ Bedrock streaming successful")
          {:error, reason} ->
            IO.puts("\n❌ Bedrock streaming failed: #{inspect(reason)}")
        end
      rescue
        e ->
          IO.puts("\n💥 Bedrock streaming crashed: #{Exception.message(e)}")
      end
    else
      IO.puts("⏭️  Skipping live test (AWS credentials not found)")
      IO.puts("   Set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION to test")
    end
  end

  def run() do
    test_bedrock_pipeline()
    test_bedrock_with_credentials()
  end
end

BedrockTest.run()