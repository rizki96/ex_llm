defmodule ExLLM.ChatBuilderTest do
  use ExUnit.Case, async: true

  alias ExLLM.ChatBuilder
  alias ExLLM.Plugs

  @moduledoc """
  Tests for the ExLLM.ChatBuilder fluent API, focusing on pipeline
  customization and manipulation capabilities.
  """

  describe "basic builder functionality" do
    test "creates builder with provider and messages" do
      messages = [%{role: "user", content: "Hello"}]
      builder = ExLLM.build(:openai, messages)

      assert %ChatBuilder{} = builder
      assert builder.request.provider == :openai
      assert builder.request.messages == messages
    end

    test "with_model sets model option" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_model("gpt-4-turbo")

      assert builder.request.options.model == "gpt-4-turbo"
    end

    test "with_temperature sets temperature option" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_temperature(0.7)

      assert builder.request.options.temperature == 0.7
    end

    test "with_max_tokens sets max_tokens option" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_max_tokens(1000)

      assert builder.request.options.max_tokens == 1000
    end

    test "chaining multiple option setters" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_model("gpt-4")
        |> ExLLM.with_temperature(0.5)
        |> ExLLM.with_max_tokens(2000)

      assert builder.request.options.model == "gpt-4"
      assert builder.request.options.temperature == 0.5
      assert builder.request.options.max_tokens == 2000
    end
  end

  describe "pipeline customization" do
    test "with_cache replaces cache plug configuration" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_cache(ttl: 3600)

      assert {:replace, Plugs.Cache, [ttl: 3600]} in builder.pipeline_mods
    end

    test "without_cache removes cache plug" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.without_cache()

      assert {:remove, Plugs.Cache} in builder.pipeline_mods
    end

    test "without_cost_tracking removes cost tracking plug" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.without_cost_tracking()

      assert {:remove, Plugs.TrackCost} in builder.pipeline_mods
    end

    test "with_custom_plug appends custom plug" do
      messages = [%{role: "user", content: "test"}]

      defmodule TestPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_custom_plug(TestPlug, some_opt: true)

      assert {:append, TestPlug, [some_opt: true]} in builder.pipeline_mods
    end

    test "with_context_strategy replaces context management plug" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_context_strategy(:sliding_window, max_tokens: 8000)

      expected = {:replace, Plugs.ManageContext, [strategy: :sliding_window, max_tokens: 8000]}
      assert expected in builder.pipeline_mods
    end
  end

  describe "pipeline manipulation methods" do
    test "insert_before adds plug before target" do
      messages = [%{role: "user", content: "test"}]

      defmodule BeforePlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.ChatBuilder.insert_before(Plugs.ExecuteRequest, BeforePlug)

      expected = {:insert_before, Plugs.ExecuteRequest, BeforePlug, []}
      assert expected in builder.pipeline_mods
    end

    test "insert_after adds plug after target" do
      messages = [%{role: "user", content: "test"}]

      defmodule AfterPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.ChatBuilder.insert_after(Plugs.FetchConfiguration, AfterPlug, opt: true)

      expected = {:insert_after, Plugs.FetchConfiguration, AfterPlug, [opt: true]}
      assert expected in builder.pipeline_mods
    end

    test "replace_plug removes old and adds new plug" do
      messages = [%{role: "user", content: "test"}]

      defmodule CustomCache do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.ChatBuilder.replace_plug(Plugs.Cache, CustomCache, ttl: 7200)

      assert {:remove, Plugs.Cache} in builder.pipeline_mods
      assert {:append, CustomCache, [ttl: 7200]} in builder.pipeline_mods
    end

    test "with_pipeline sets custom pipeline" do
      messages = [%{role: "user", content: "test"}]

      custom_pipeline = [
        Plugs.ValidateProvider,
        Plugs.FetchConfiguration,
        Plugs.ExecuteRequest
      ]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.ChatBuilder.with_pipeline(custom_pipeline)

      assert [{:custom_pipeline, ^custom_pipeline}] = builder.pipeline_mods
    end
  end

  describe "inspect_pipeline" do
    test "returns default pipeline when no modifications" do
      messages = [%{role: "user", content: "test"}]

      builder = ExLLM.build(:openai, messages)
      pipeline = ExLLM.inspect_pipeline(builder)

      # Should return the default OpenAI chat pipeline
      assert is_list(pipeline)
      assert length(pipeline) > 0

      # Check for expected plugs in default pipeline
      plug_modules = extract_plug_modules(pipeline)
      assert Plugs.ValidateProvider in plug_modules
      assert Plugs.FetchConfiguration in plug_modules
      assert Plugs.BuildTeslaClient in plug_modules
    end

    test "returns modified pipeline after customizations" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.without_cache()
        |> ExLLM.without_cost_tracking()

      pipeline = ExLLM.inspect_pipeline(builder)
      plug_modules = extract_plug_modules(pipeline)

      # Cache and cost tracking should be removed
      refute Plugs.Cache in plug_modules
      refute Plugs.TrackCost in plug_modules

      # Other plugs should remain
      assert Plugs.ValidateProvider in plug_modules
      assert Plugs.ExecuteRequest in plug_modules
    end

    test "returns custom pipeline when set" do
      messages = [%{role: "user", content: "test"}]

      custom_pipeline = [
        Plugs.ValidateProvider,
        {Plugs.FetchConfiguration, [custom: true]},
        Plugs.ExecuteRequest
      ]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.ChatBuilder.with_pipeline(custom_pipeline)

      pipeline = ExLLM.inspect_pipeline(builder)

      assert pipeline == custom_pipeline
    end
  end

  describe "debug_info" do
    test "provides builder state information" do
      messages = [
        %{role: "system", content: "Be helpful"},
        %{role: "user", content: "Hello"}
      ]

      builder =
        ExLLM.build(:anthropic, messages)
        |> ExLLM.with_model("claude-3-opus")
        |> ExLLM.with_temperature(0.5)
        |> ExLLM.without_cache()

      info = ExLLM.debug_info(builder)

      assert info.provider == :anthropic
      assert info.message_count == 2
      assert info.options.model == "claude-3-opus"
      assert info.options.temperature == 0.5
      # only without_cache is a pipeline mod
      assert info.pipeline_modifications == 1
      assert info.streaming == false
      assert info.has_custom_pipeline == false
    end

    test "detects custom pipeline" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.ChatBuilder.with_pipeline([Plugs.ExecuteRequest])

      info = ExLLM.debug_info(builder)

      assert info.has_custom_pipeline == true
    end
  end

  describe "pipeline ordering validation" do
    test "insert_before maintains correct order in final pipeline" do
      messages = [%{role: "user", content: "test"}]

      defmodule OrderTestPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      # Use openai provider which has ExecuteRequest in its pipeline
      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.ChatBuilder.insert_before(Plugs.ExecuteRequest, OrderTestPlug)

      pipeline = ExLLM.inspect_pipeline(builder)
      plug_modules = extract_plug_modules(pipeline)

      # Find positions
      order_test_idx = Enum.find_index(plug_modules, &(&1 == OrderTestPlug))
      execute_idx = Enum.find_index(plug_modules, &(&1 == Plugs.ExecuteRequest))

      assert order_test_idx != nil
      assert execute_idx != nil
      assert order_test_idx < execute_idx
    end

    test "insert_after maintains correct order in final pipeline" do
      messages = [%{role: "user", content: "test"}]

      defmodule AfterTestPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:mock, messages)
        |> ExLLM.ChatBuilder.insert_after(Plugs.ValidateProvider, AfterTestPlug)

      pipeline = ExLLM.inspect_pipeline(builder)
      plug_modules = extract_plug_modules(pipeline)

      # Find positions
      validate_idx = Enum.find_index(plug_modules, &(&1 == Plugs.ValidateProvider))
      after_test_idx = Enum.find_index(plug_modules, &(&1 == AfterTestPlug))

      assert validate_idx != nil
      assert after_test_idx != nil
      assert validate_idx < after_test_idx
    end

    test "multiple modifications are applied in order" do
      messages = [%{role: "user", content: "test"}]

      defmodule FirstCustomPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      defmodule SecondCustomPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:mock, messages)
        |> ExLLM.without_cache()
        |> ExLLM.with_custom_plug(FirstCustomPlug)
        |> ExLLM.with_custom_plug(SecondCustomPlug)

      pipeline = ExLLM.inspect_pipeline(builder)
      plug_modules = extract_plug_modules(pipeline)

      # Cache should be removed
      refute Plugs.Cache in plug_modules

      # Custom plugs should be appended in order
      first_idx = Enum.find_index(plug_modules, &(&1 == FirstCustomPlug))
      second_idx = Enum.find_index(plug_modules, &(&1 == SecondCustomPlug))

      assert first_idx != nil
      assert second_idx != nil
      assert first_idx < second_idx
    end
  end

  describe "error scenarios" do
    test "handles insert_before with non-existent target" do
      messages = [%{role: "user", content: "test"}]

      defmodule OrphanPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:mock, messages)
        |> ExLLM.ChatBuilder.insert_before(NonExistentPlug, OrphanPlug)

      pipeline = ExLLM.inspect_pipeline(builder)
      plug_modules = extract_plug_modules(pipeline)

      # The plug should be added at the end if target not found
      assert OrphanPlug in plug_modules
    end

    test "handles replace_plug with non-existent target" do
      messages = [%{role: "user", content: "test"}]

      defmodule ReplacementPlug do
        use ExLLM.Plug
        def call(request, _opts), do: request
      end

      builder =
        ExLLM.build(:mock, messages)
        |> ExLLM.ChatBuilder.replace_plug(NonExistentPlug, ReplacementPlug)

      pipeline = ExLLM.inspect_pipeline(builder)
      plug_modules = extract_plug_modules(pipeline)

      # Should still add the replacement plug even if target doesn't exist
      assert ReplacementPlug in plug_modules
    end
  end

  # Helper functions

  defp extract_plug_modules(pipeline) do
    Enum.map(pipeline, fn
      {module, _opts} -> module
      module -> module
    end)
  end
end
