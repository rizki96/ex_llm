defmodule ExLLM.InstructorIntegrationTest do
  use ExUnit.Case
  import ExLLM.Testing.CapabilityHelpers

  @moduletag :integration

  # Test schema for structured outputs
  defmodule Person do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:name, :string)
      field(:age, :integer)
      field(:occupation, :string)
    end
  end

  defmodule MathResult do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:expression, :string)
      field(:result, :float)
      field(:explanation, :string)
    end
  end

  describe "instructor with real providers" do
    test "extracts structured data using response_model with Anthropic" do
      skip_unless_configured_and_supports(:anthropic, :chat)

      messages = [
        %{
          role: "user",
          content: "Extract person info: Alice Johnson is a 28-year-old data scientist."
        }
      ]

      case ExLLM.chat(:anthropic, messages,
             response_model: Person,
             temperature: 0.1,
             max_tokens: 100
           ) do
        {:ok, person} ->
          assert person.name == "Alice Johnson"
          assert person.age == 28
          assert person.occupation == "data scientist"

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("Instructor extraction failed: #{inspect(reason)}")
      end
    end

    test "extracts structured data using response_model with OpenAI" do
      skip_unless_configured_and_supports(:openai, :chat)

      messages = [
        %{
          role: "user",
          content: "Extract person info: Bob Smith is a 35-year-old teacher."
        }
      ]

      case ExLLM.chat(:openai, messages,
             response_model: Person,
             temperature: 0.1,
             max_tokens: 100
           ) do
        {:ok, person} ->
          assert person.name == "Bob Smith"
          assert person.age == 35
          assert person.occupation == "teacher"

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("Instructor extraction failed: #{inspect(reason)}")
      end
    end

    test "handles validation and retries with real provider" do
      skip_unless_configured_and_supports(:anthropic, :chat)

      messages = [
        %{
          role: "user",
          content: "Calculate: What is 15 + 27? Show your work."
        }
      ]

      case ExLLM.chat(:anthropic, messages,
             response_model: MathResult,
             temperature: 0.1,
             max_tokens: 200,
             max_retries: 2
           ) do
        {:ok, result} ->
          assert result.expression =~ "15" or result.expression =~ "27"
          assert result.result == 42.0
          assert is_binary(result.explanation)
          assert String.length(result.explanation) > 0

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("Math calculation failed: #{inspect(reason)}")
      end
    end

    test "handles lists and arrays with real provider" do
      skip_unless_configured_and_supports(:openai, :chat)

      # Define a schema with a list
      defmodule TodoList do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          field(:title, :string)
          field(:items, {:array, :string})
        end
      end

      messages = [
        %{
          role: "user",
          content: "Create a todo list for grocery shopping: milk, bread, eggs, cheese"
        }
      ]

      case ExLLM.chat(:openai, messages,
             response_model: TodoList,
             temperature: 0.1,
             max_tokens: 100
           ) do
        {:ok, todo_list} ->
          assert todo_list.title =~ "grocery" or todo_list.title =~ "shopping"
          assert is_list(todo_list.items)
          assert length(todo_list.items) >= 3
          # Check for at least some of the items
          items_text = Enum.join(todo_list.items, " ")
          assert items_text =~ "milk" or items_text =~ "bread" or items_text =~ "eggs"

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("List extraction failed: #{inspect(reason)}")
      end
    end

    test "falls back to JSON mode when needed with real provider" do
      skip_unless_configured_and_supports(:anthropic, :chat)

      messages = [
        %{
          role: "user",
          content: "Return a JSON object with name and age for John Doe, 30 years old"
        }
      ]

      # When response_model is not provided, should get raw JSON
      case ExLLM.chat(:anthropic, messages, temperature: 0, max_tokens: 100) do
        {:ok, response} ->
          # Try to parse the response as JSON
          case Jason.decode(response.content) do
            {:ok, json} ->
              assert is_map(json)
              # Provider might return with different key casing
              assert Map.get(json, "name") == "John Doe" or
                       Map.get(json, "Name") == "John Doe"

              assert Map.get(json, "age") == 30 or
                       Map.get(json, "Age") == 30

            {:error, _} ->
              # If not valid JSON, at least verify we got some response
              assert String.contains?(response.content, "John") or
                       String.contains?(response.content, "30")
          end

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("JSON response failed: #{inspect(reason)}")
      end
    end

    test "handles complex nested structures with real provider" do
      skip_unless_configured_and_supports(:openai, :chat)

      # Define a nested structure
      defmodule Company do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          field(:name, :string)
          field(:founded, :integer)
          embeds_many(:employees, Person)
        end
      end

      messages = [
        %{
          role: "user",
          content: """
          Extract company info:
          TechCorp was founded in 2020. 
          Employees: Jane Doe (25, engineer) and Bob Lee (30, manager)
          """
        }
      ]

      case ExLLM.chat(:openai, messages,
             response_model: Company,
             temperature: 0.1,
             max_tokens: 300
           ) do
        {:ok, company} ->
          assert company.name == "TechCorp"
          assert company.founded == 2020
          assert length(company.employees) == 2

          jane = Enum.find(company.employees, &(&1.name =~ "Jane"))
          assert jane.age == 25
          assert jane.occupation == "engineer"

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("Complex structure extraction failed: #{inspect(reason)}")
      end
    end
  end
end
