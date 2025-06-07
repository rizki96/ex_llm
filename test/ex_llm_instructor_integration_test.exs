defmodule ExLLM.InstructorIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  # Test schema
  defmodule TestPerson do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:name, :string)
      field(:age, :integer)
      field(:occupation, :string)
    end

    def changeset(struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:name, :age, :occupation])
      |> Ecto.Changeset.validate_required([:name])
      |> Ecto.Changeset.validate_number(:age, greater_than: 0, less_than: 150)
    end
  end

  setup do
    # Since these are integration tests, we'll use the mock adapter
    # to test the Instructor functionality without requiring API keys
    case ExLLM.Adapters.Mock.start_link() do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        # Reset if already started
        ExLLM.Adapters.Mock.reset()
        :ok
    end

    # Set up a mock response handler that returns structured JSON
    ExLLM.Adapters.Mock.set_response_handler(fn messages, _options ->
      last_message = List.last(messages)
      content = last_message.content || last_message[:content] || last_message["content"]

      response =
        cond do
          String.contains?(content, "John Doe") ->
            ~s({"name": "John Doe", "age": 30, "occupation": "software engineer"})

          String.contains?(content, "Jane Smith") ->
            ~s({"name": "Jane Smith", "age": 25, "occupation": "doctor"})

          String.contains?(content, "Implement instructor support") ->
            ~s({"title": "Implement instructor support", "completed": true, "priority": 3, "tags": ["elixir", "llm", "structured-output"]})

          String.contains?(content, "count to") ->
            "[1, 2, 3, 4, 5]"

          String.contains?(content, "Extract the person") ->
            ~s({"name": "Alice Johnson", "age": 28})

          String.contains?(content, "Return JSON") and String.contains?(content, "Alice Brown") ->
            ~s({"name": "Alice Brown", "age": 28, "occupation": "designer"})

          true ->
            ~s({"data": "test"})
        end

      %{
        content: response,
        model: "mock-model",
        usage: %{input_tokens: 10, output_tokens: 20}
      }
    end)

    :ok
  end

  describe "structured output integration" do
    @tag :integration
    test "extracts structured data using response_model in main module" do
      messages = [
        %{
          role: "user",
          content: "Extract person info: John Doe is a 30-year-old software engineer."
        }
      ]

      assert {:ok, person} =
               ExLLM.chat(:mock, messages,
                 response_model: TestPerson,
                 temperature: 0.1
               )

      assert person.name == "John Doe"
      assert person.age == 30
      assert person.occupation == "software engineer"
    end

    @tag :integration
    test "validates and retries on validation errors" do
      messages = [
        %{
          role: "user",
          content: "Extract person info but make age negative: Jane Smith, -25 years old, doctor."
        }
      ]

      # With retries, it should correct the invalid age
      assert {:ok, person} =
               ExLLM.chat(:mock, messages,
                 response_model: TestPerson,
                 max_retries: 2,
                 temperature: 0.1
               )

      assert person.name == "Jane Smith"
      # Should be corrected
      assert person.age > 0
      assert person.occupation == "doctor"
    end

    @tag :integration
    test "works with simple type specifications" do
      type_spec = %{
        title: :string,
        completed: :boolean,
        priority: :integer,
        tags: {:array, :string}
      }

      messages = [
        %{
          role: "user",
          content: """
          Extract task info:
          Title: Implement instructor support
          Status: Done
          Priority: High (score 3)
          Tags: elixir, llm, structured-output
          """
        }
      ]

      assert {:ok, task} =
               ExLLM.chat(:mock, messages,
                 response_model: type_spec,
                 temperature: 0.1
               )

      assert task.title == "Implement instructor support"
      assert task.completed == true
      assert task.priority == 3
      assert "elixir" in task.tags
      assert "llm" in task.tags
      assert "structured-output" in task.tags
    end

    @tag :integration
    test "parse_response works with existing LLM response" do
      # First get a regular response
      messages = [
        %{
          role: "user",
          content:
            "Return JSON: {\"name\": \"Alice Brown\", \"age\": 28, \"occupation\": \"designer\"}"
        }
      ]

      assert {:ok, response} = ExLLM.chat(:mock, messages, temperature: 0)

      # Then parse it into a structure
      assert {:ok, person} = ExLLM.Instructor.parse_response(response, TestPerson)

      assert person.name == "Alice Brown"
      assert person.age == 28
      assert person.occupation == "designer"
    end

    @tag :integration
    test "returns appropriate error for unsupported provider" do
      messages = [%{role: "user", content: "Test"}]

      assert {:error, :unsupported_provider_for_instructor} =
               ExLLM.chat(:local, messages, response_model: TestPerson)
    end
  end
end
