defmodule ExLLM.Gemini.CachingUnitTest do
  @moduledoc """
  Unit tests for the Gemini Context Caching API.
  
  Tests internal functions and behavior without making actual API calls.
  """
  
  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Caching
  alias ExLLM.Gemini.Caching.{CachedContent, UsageMetadata}
  alias ExLLM.Gemini.Content.{Content, Part}
  
  describe "CachedContent struct" do
    test "creates cached content with all fields" do
      cached = %CachedContent{
        name: "cachedContents/test-123",
        display_name: "Test Cache",
        model: "models/gemini-2.0-flash",
        system_instruction: %Content{
          role: "system",
          parts: [%Part{text: "System instruction"}]
        },
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Cached content"}]
          }
        ],
        tools: [],
        tool_config: nil,
        create_time: ~U[2024-01-01 12:00:00Z],
        update_time: ~U[2024-01-01 12:01:00Z],
        expire_time: ~U[2024-01-01 13:00:00Z],
        ttl: nil,
        usage_metadata: %UsageMetadata{total_token_count: 100}
      }
      
      assert cached.name == "cachedContents/test-123"
      assert cached.display_name == "Test Cache"
      assert cached.model == "models/gemini-2.0-flash"
      assert cached.usage_metadata.total_token_count == 100
    end
    
    test "creates minimal cached content" do
      cached = %CachedContent{
        name: "cachedContents/minimal",
        model: "models/gemini-2.0-flash",
        expire_time: ~U[2024-01-01 12:00:00Z]
      }
      
      assert cached.name == "cachedContents/minimal"
      assert cached.display_name == nil
      assert cached.contents == nil
      assert cached.tools == nil
    end
  end
  
  describe "UsageMetadata struct" do
    test "creates usage metadata" do
      metadata = %UsageMetadata{
        total_token_count: 500
      }
      
      assert metadata.total_token_count == 500
    end
  end
  
  describe "validate_cached_content_name/1" do
    test "validates proper cached content names" do
      assert Caching.validate_cached_content_name("cachedContents/abc-123") == :ok
      assert Caching.validate_cached_content_name("cachedContents/test-content-456") == :ok
    end
    
    test "returns error for invalid formats" do
      assert {:error, %{reason: :invalid_params}} = Caching.validate_cached_content_name("abc-123")
      assert {:error, %{reason: :invalid_params}} = Caching.validate_cached_content_name("cachedContents/")
      assert {:error, %{reason: :invalid_params}} = Caching.validate_cached_content_name("")
      assert {:error, %{reason: :invalid_params}} = Caching.validate_cached_content_name(nil)
    end
  end
  
  describe "validate_page_size/1" do
    test "validates valid page sizes" do
      assert Caching.validate_page_size(1) == :ok
      assert Caching.validate_page_size(500) == :ok
      assert Caching.validate_page_size(1000) == :ok
    end
    
    test "returns error for invalid page sizes" do
      assert {:error, %{reason: :invalid_params}} = Caching.validate_page_size(0)
      assert {:error, %{reason: :invalid_params}} = Caching.validate_page_size(-1)
      assert {:error, %{reason: :invalid_params}} = Caching.validate_page_size(1001)
      assert {:error, %{reason: :invalid_params}} = Caching.validate_page_size("10")
    end
  end
  
  describe "validate_create_request/1" do
    test "validates complete request with TTL" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        model: "models/gemini-2.0-flash",
        ttl: "3600s"
      }
      
      assert Caching.validate_create_request(request) == :ok
    end
    
    test "validates complete request with expire_time" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        model: "models/gemini-2.0-flash",
        expire_time: "2024-01-01T12:00:00Z"
      }
      
      assert Caching.validate_create_request(request) == :ok
    end
    
    test "returns error for missing model" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        ttl: "3600s"
      }
      
      assert {:error, %{reason: :invalid_params, message: message}} = Caching.validate_create_request(request)
      assert message =~ "model"
    end
    
    test "returns error for missing expiration" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        model: "models/gemini-2.0-flash"
      }
      
      assert {:error, %{reason: :invalid_params, message: message}} = Caching.validate_create_request(request)
      assert message =~ "TTL or expire_time"
    end
    
    test "returns error for both TTL and expire_time" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        model: "models/gemini-2.0-flash",
        ttl: "3600s",
        expire_time: "2024-01-01T12:00:00Z"
      }
      
      assert {:error, %{reason: :invalid_params, message: message}} = Caching.validate_create_request(request)
      assert message =~ "both"
    end
  end
  
  describe "validate_update_request/1" do
    test "validates update with TTL" do
      request = %{ttl: "7200s"}
      assert Caching.validate_update_request(request) == :ok
    end
    
    test "validates update with expire_time" do
      request = %{expire_time: "2024-01-01T12:00:00Z"}
      assert Caching.validate_update_request(request) == :ok
    end
    
    test "returns error for empty update" do
      request = %{}
      assert {:error, %{reason: :invalid_params}} = Caching.validate_update_request(request)
    end
    
    test "returns error for both TTL and expire_time" do
      request = %{
        ttl: "7200s",
        expire_time: "2024-01-01T12:00:00Z"
      }
      
      assert {:error, %{reason: :invalid_params}} = Caching.validate_update_request(request)
    end
    
    test "returns error for non-updatable fields" do
      request = %{model: "models/gemini-1.5-pro"}
      assert {:error, %{reason: :invalid_params}} = Caching.validate_update_request(request)
      
      request = %{contents: []}
      assert {:error, %{reason: :invalid_params}} = Caching.validate_update_request(request)
    end
  end
  
  describe "parse_ttl/1" do
    test "parses valid TTL strings" do
      assert Caching.parse_ttl("3600s") == {:ok, 3600.0}
      assert Caching.parse_ttl("1800s") == {:ok, 1800.0}
      assert Caching.parse_ttl("60s") == {:ok, 60.0}
      assert Caching.parse_ttl("3600.5s") == {:ok, 3600.5}
    end
    
    test "returns error for invalid TTL" do
      assert {:error, :invalid_ttl} = Caching.parse_ttl("3600")
      assert {:error, :invalid_ttl} = Caching.parse_ttl("invalid")
      assert {:error, :invalid_ttl} = Caching.parse_ttl(nil)
      assert {:error, :invalid_ttl} = Caching.parse_ttl("")
    end
  end
  
  describe "build_create_request_body/1" do
    test "builds request with TTL" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        model: "models/gemini-2.0-flash",
        ttl: "3600s",
        display_name: "Test"
      }
      
      body = Caching.build_create_request_body(request)
      
      assert body["contents"]
      assert body["model"] == "models/gemini-2.0-flash"
      assert body["ttl"] == "3600s"
      assert body["displayName"] == "Test"
      refute Map.has_key?(body, "expireTime")
    end
    
    test "builds request with expire_time" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        model: "models/gemini-2.0-flash",
        expire_time: "2024-01-01T12:00:00Z"
      }
      
      body = Caching.build_create_request_body(request)
      
      assert body["contents"]
      assert body["model"] == "models/gemini-2.0-flash"
      assert body["expireTime"] == "2024-01-01T12:00:00Z"
      refute Map.has_key?(body, "ttl")
    end
    
    test "includes optional fields when present" do
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "content"}]}],
        model: "models/gemini-2.0-flash",
        ttl: "3600s",
        system_instruction: %Content{role: "system", parts: [%Part{text: "instruction"}]},
        tools: [%{function_declarations: []}],
        tool_config: %{function_calling_config: %{mode: "AUTO"}}
      }
      
      body = Caching.build_create_request_body(request)
      
      assert body["systemInstruction"]
      assert body["tools"]
      assert body["toolConfig"]
    end
  end
  
  describe "build_update_request_body/1" do
    test "builds update with TTL" do
      request = %{ttl: "7200s"}
      body = Caching.build_update_request_body(request)
      
      assert body == %{"ttl" => "7200s"}
    end
    
    test "builds update with expire_time" do
      request = %{expire_time: "2024-01-01T12:00:00Z"}
      body = Caching.build_update_request_body(request)
      
      assert body == %{"expireTime" => "2024-01-01T12:00:00Z"}
    end
  end
  
  describe "build_update_mask/1" do
    test "builds update mask for TTL" do
      request = %{ttl: "7200s"}
      assert Caching.build_update_mask(request) == "ttl"
    end
    
    test "builds update mask for expire_time" do
      request = %{expire_time: "2024-01-01T12:00:00Z"}
      assert Caching.build_update_mask(request) == "expireTime"
    end
  end
  
  describe "normalize_model_name/1" do
    test "handles various model name formats" do
      assert Caching.normalize_model_name("gemini-2.0-flash") == "models/gemini-2.0-flash"
      assert Caching.normalize_model_name("models/gemini-2.0-flash") == "models/gemini-2.0-flash"
      assert Caching.normalize_model_name("gemini/gemini-2.0-flash") == "models/gemini-2.0-flash"
    end
  end
end