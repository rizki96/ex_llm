defmodule ExLLM.InstructorTest do
  use ExUnit.Case, async: true
  alias ExLLM.Instructor

  # Sample schema for testing
  defmodule TestSchema do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:name, :string)
      field(:age, :integer)
      field(:active, :boolean)
    end

    def changeset(struct, params) do
      struct
      |> Ecto.Changeset.cast(params, [:name, :age, :active])
      |> Ecto.Changeset.validate_required([:name, :age])
      |> Ecto.Changeset.validate_number(:age, greater_than: 0)
    end
  end

  describe "available?/0" do
    test "returns boolean indicating if instructor is available" do
      assert is_boolean(Instructor.available?())
    end
  end

  describe "chat/3" do
    @tag :skip_unless_instructor
    test "returns error when instructor is not available and it's not loaded" do
      # This test will be skipped if instructor is available
      unless Instructor.available?() do
        messages = [%{role: "user", content: "Test"}]

        assert {:error, :instructor_not_available} =
                 Instructor.chat(:anthropic, messages, response_model: TestSchema)
      end
    end

    @tag :skip_unless_instructor
    test "returns error for unsupported provider" do
      if Instructor.available?() do
        messages = [%{role: "user", content: "Test"}]

        # :local is not supported by instructor
        assert {:error, :unsupported_provider_for_instructor} =
                 Instructor.chat(:local, messages, response_model: TestSchema)
      end
    end

    @tag :skip_unless_instructor
    test "validates response_model is required" do
      if Instructor.available?() do
        messages = [%{role: "user", content: "Test"}]

        assert_raise KeyError, fn ->
          Instructor.chat(:anthropic, messages, [])
        end
      end
    end
  end

  describe "parse_response/2" do
    test "returns error when instructor is not available" do
      unless Instructor.available?() do
        response = %ExLLM.Types.LLMResponse{
          content: ~s({"name": "John", "age": 30}),
          model: "test-model"
        }

        assert {:error, :instructor_not_available} =
                 Instructor.parse_response(response, TestSchema)
      end
    end

    @tag :skip_unless_instructor
    test "parses valid JSON response into schema" do
      if Instructor.available?() do
        response = %ExLLM.Types.LLMResponse{
          content: ~s({"name": "John", "age": 30, "active": true}),
          model: "test-model"
        }

        assert {:ok, result} = Instructor.parse_response(response, TestSchema)
        assert result.name == "John"
        assert result.age == 30
        assert result.active == true
      end
    end

    @tag :skip_unless_instructor
    test "returns error for invalid JSON" do
      if Instructor.available?() do
        response = %ExLLM.Types.LLMResponse{
          content: "not valid json",
          model: "test-model"
        }

        assert {:error, {:json_decode_error, _}} =
                 Instructor.parse_response(response, TestSchema)
      end
    end

    @tag :skip_unless_instructor
    test "returns validation error for invalid data" do
      if Instructor.available?() do
        response = %ExLLM.Types.LLMResponse{
          content: ~s({"name": "John", "age": -5}),
          model: "test-model"
        }

        assert {:error, {:validation_failed, _}} =
                 Instructor.parse_response(response, TestSchema)
      end
    end

    @tag :skip_unless_instructor
    test "parses response with simple type spec" do
      if Instructor.available?() do
        response = %ExLLM.Types.LLMResponse{
          content: ~s({"name": "John", "age": 30, "tags": ["developer", "elixir"]}),
          model: "test-model"
        }

        type_spec = %{
          name: :string,
          age: :integer,
          tags: {:array, :string}
        }

        assert {:ok, result} = Instructor.parse_response(response, type_spec)
        assert result.name == "John"
        assert result.age == 30
        assert result.tags == ["developer", "elixir"]
      end
    end
  end

  describe "simple_schema/2" do
    test "returns error indicating to use type specs" do
      fields = %{name: :string, age: :integer}

      assert {:error, :use_type_spec_instead} = Instructor.simple_schema(fields)
    end
  end

  describe "integration with main module" do
    test "ExLLM.chat/3 returns error when response_model is used without instructor" do
      unless Instructor.available?() do
        messages = [%{role: "user", content: "Test"}]

        assert {:error, :instructor_not_available} =
                 ExLLM.chat(:anthropic, messages, response_model: TestSchema)
      end
    end
  end
end
