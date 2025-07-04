defmodule ExLLM.Testing.Fixtures do
  @moduledoc """
  Provides minimal test fixtures for integration tests.

  All fixtures are designed to be as small as possible to minimize
  API costs while still testing functionality.
  """

  @fixtures_dir "test/fixtures"

  def ensure_fixtures_exist do
    File.mkdir_p!(@fixtures_dir)
    create_text_fixtures()
    create_json_fixtures()
    create_csv_fixtures()
    create_training_fixtures()
  end

  # File fixtures for upload tests

  def text_file_path, do: Path.join(@fixtures_dir, "sample.txt")
  def json_file_path, do: Path.join(@fixtures_dir, "sample.json")
  def csv_file_path, do: Path.join(@fixtures_dir, "sample.csv")
  def pdf_file_path, do: Path.join(@fixtures_dir, "sample.pdf")
  def jsonl_file_path, do: Path.join(@fixtures_dir, "training.jsonl")

  def minimal_text_content do
    "Hello ExLLM"
  end

  def minimal_json_content do
    %{
      "name" => "test",
      "value" => 42
    }
  end

  def minimal_csv_content do
    "name,value\ntest,42"
  end

  def minimal_training_data do
    [
      %{
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant."},
          %{"role" => "user", "content" => "Hello"},
          %{"role" => "assistant", "content" => "Hi there!"}
        ]
      },
      %{
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant."},
          %{"role" => "user", "content" => "What is 2+2?"},
          %{"role" => "assistant", "content" => "2+2 equals 4."}
        ]
      }
    ]
  end

  # Message fixtures for chat tests

  def minimal_messages do
    [
      %{role: "user", content: "Hi"}
    ]
  end

  def conversation_messages do
    [
      %{role: "user", content: "What is 2+2?"},
      %{role: "assistant", content: "2+2 equals 4."},
      %{role: "user", content: "Thanks!"}
    ]
  end

  # Assistant fixtures

  def minimal_assistant_config do
    %{
      name: "Test Assistant #{unique_id()}",
      instructions: "You are a test assistant.",
      model: "gpt-3.5-turbo"
    }
  end

  def minimal_function_tool do
    %{
      type: "function",
      function: %{
        name: "get_weather",
        description: "Get weather for a location",
        parameters: %{
          type: "object",
          properties: %{
            location: %{type: "string"}
          },
          required: ["location"]
        }
      }
    }
  end

  # Knowledge base fixtures

  def minimal_document do
    %{
      content: "ExLLM is a unified Elixir client for Large Language Models.",
      metadata: %{
        source: "test",
        category: "documentation"
      }
    }
  end

  def search_documents do
    [
      %{
        content: "ExLLM supports OpenAI, Anthropic, and Gemini providers.",
        metadata: %{category: "features"}
      },
      %{
        content: "ExLLM provides streaming and function calling capabilities.",
        metadata: %{category: "features"}
      },
      %{
        content: "ExLLM tracks costs and manages sessions.",
        metadata: %{category: "features"}
      }
    ]
  end

  # Batch processing fixtures

  def batch_messages(count \\ 3) do
    Enum.map(1..count, fn i ->
      %{
        id: "batch_#{i}",
        messages: [%{role: "user", content: "Item #{i}"}]
      }
    end)
  end

  # Context caching fixtures

  def cacheable_context do
    """
    You are an AI assistant with knowledge about ExLLM.
    ExLLM is a unified Elixir client for Large Language Models.
    It supports multiple providers and advanced features.
    """
  end

  # Helper functions

  def unique_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end

  def cleanup_fixtures do
    File.rm_rf!(@fixtures_dir)
  end

  # Private functions

  defp create_text_fixtures do
    File.write!(text_file_path(), minimal_text_content())
  end

  defp create_json_fixtures do
    File.write!(json_file_path(), Jason.encode!(minimal_json_content()))
  end

  defp create_csv_fixtures do
    File.write!(csv_file_path(), minimal_csv_content())
  end

  defp create_training_fixtures do
    jsonl_content =
      minimal_training_data()
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    File.write!(jsonl_file_path(), jsonl_content)
  end

  # Note: PDF creation is more complex, so we'll create a minimal valid PDF
  def create_minimal_pdf do
    # This is a minimal valid PDF that just says "Hello"
    pdf_content = <<
      # %PDF-1.1
      0x25,
      0x50,
      0x44,
      0x46,
      0x2D,
      0x31,
      0x2E,
      0x31,
      0x0A,
      # 1 0 obj
      0x31,
      0x20,
      0x30,
      0x20,
      0x6F,
      0x62,
      0x6A,
      0x0A,
      # << /Type
      0x3C,
      0x3C,
      0x20,
      0x2F,
      0x54,
      0x79,
      0x70,
      0x65,
      0x20,
      # /Catalog
      0x2F,
      0x43,
      0x61,
      0x74,
      0x61,
      0x6C,
      0x6F,
      0x67,
      0x20,
      # /Pages 2
      0x2F,
      0x50,
      0x61,
      0x67,
      0x65,
      0x73,
      0x20,
      0x32,
      0x20,
      # 0 R >>
      0x30,
      0x20,
      0x52,
      0x20,
      0x3E,
      0x3E,
      0x0A,
      # endobj
      0x65,
      0x6E,
      0x64,
      0x6F,
      0x62,
      0x6A,
      0x0A,
      # 2 0 obj
      0x32,
      0x20,
      0x30,
      0x20,
      0x6F,
      0x62,
      0x6A,
      0x0A,
      # << /Type
      0x3C,
      0x3C,
      0x20,
      0x2F,
      0x54,
      0x79,
      0x70,
      0x65,
      0x20,
      # /Pages /K
      0x2F,
      0x50,
      0x61,
      0x67,
      0x65,
      0x73,
      0x20,
      0x2F,
      0x4B,
      # ids [3 0
      0x69,
      0x64,
      0x73,
      0x20,
      0x5B,
      0x33,
      0x20,
      0x30,
      0x20,
      # R] /Count
      0x52,
      0x5D,
      0x20,
      0x2F,
      0x43,
      0x6F,
      0x75,
      0x6E,
      0x74,
      # 1 >>
      0x20,
      0x31,
      0x20,
      0x3E,
      0x3E,
      0x0A,
      # endobj
      0x65,
      0x6E,
      0x64,
      0x6F,
      0x62,
      0x6A,
      0x0A,
      # 3 0 obj
      0x33,
      0x20,
      0x30,
      0x20,
      0x6F,
      0x62,
      0x6A,
      0x0A,
      # << /Type
      0x3C,
      0x3C,
      0x20,
      0x2F,
      0x54,
      0x79,
      0x70,
      0x65,
      0x20,
      # /Page /Pa
      0x2F,
      0x50,
      0x61,
      0x67,
      0x65,
      0x20,
      0x2F,
      0x50,
      0x61,
      # rent 2 0
      0x72,
      0x65,
      0x6E,
      0x74,
      0x20,
      0x32,
      0x20,
      0x30,
      0x20,
      # R >>
      0x52,
      0x20,
      0x3E,
      0x3E,
      0x0A,
      # endobj
      0x65,
      0x6E,
      0x64,
      0x6F,
      0x62,
      0x6A,
      0x0A,
      # xref
      0x78,
      0x72,
      0x65,
      0x66,
      0x0A,
      # 0 4
      0x30,
      0x20,
      0x34,
      0x0A,
      # 000000000
      0x30,
      0x30,
      0x30,
      0x30,
      0x30,
      0x30,
      0x30,
      0x30,
      0x30,
      # 0 65535 f
      0x30,
      0x20,
      0x36,
      0x35,
      0x35,
      0x33,
      0x35,
      0x20,
      0x66,
      # \n
      0x0A
    >>

    File.write!(pdf_file_path(), pdf_content)
  end
end
