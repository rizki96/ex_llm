defmodule ExLLM.InstructorIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :skip

  # Test schema
  defmodule TestPerson do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :name, :string
      field :age, :integer
      field :occupation, :string
    end

    def changeset(struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:name, :age, :occupation])
      |> Ecto.Changeset.validate_required([:name])
      |> Ecto.Changeset.validate_number(:age, greater_than: 0, less_than: 150)
    end
  end

  setup do
    # Skip these tests if instructor is not available
    if not ExLLM.Instructor.available?() do
      :skip
    else
      # Skip if API key is not properly configured or we're in CI
      api_key = System.get_env("ANTHROPIC_API_KEY")
      skip_integration = System.get_env("SKIP_INTEGRATION_TESTS")
      
      cond do
        skip_integration == "true" ->
          :skip
          
        is_nil(api_key) or api_key == "" ->
          :skip
          
        # Check if this looks like a test/CI environment API key
        String.contains?(api_key, "test") or String.contains?(api_key, "mock") ->
          :skip
          
        true ->
          :ok
      end
    end
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
      
      assert {:ok, person} = ExLLM.chat(:anthropic, messages,
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
      assert {:ok, person} = ExLLM.chat(:anthropic, messages,
        response_model: TestPerson,
        max_retries: 2,
        temperature: 0.1
      )
      
      assert person.name == "Jane Smith"
      assert person.age > 0  # Should be corrected
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
      
      assert {:ok, task} = ExLLM.chat(:anthropic, messages,
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
          content: "Return JSON: {\"name\": \"Alice Brown\", \"age\": 28, \"occupation\": \"designer\"}"
        }
      ]
      
      assert {:ok, response} = ExLLM.chat(:anthropic, messages, temperature: 0)
      
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