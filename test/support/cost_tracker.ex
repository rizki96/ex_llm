defmodule ExLLM.Testing.CostTracker do
  @moduledoc """
  Tracks API costs during test execution to prevent budget overruns.

  Features:
  - Per-test cost limits ($0.50 default)
  - Cumulative budget tracking ($50 total)
  - Automatic test failure on overrun
  - Cost report generation
  """

  use GenServer
  require Logger

  @default_test_limit 0.50
  @total_budget_limit 50.00
  @cost_file "test/integration/.test_costs.json"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def track_request(provider, model, tokens, type \\ :completion) do
    GenServer.cast(__MODULE__, {:track_request, provider, model, tokens, type})
  end

  def check_test_budget(test_name, limit \\ @default_test_limit) do
    GenServer.call(__MODULE__, {:check_test_budget, test_name, limit})
  end

  def get_test_cost(test_name) do
    GenServer.call(__MODULE__, {:get_test_cost, test_name})
  end

  def get_total_cost do
    GenServer.call(__MODULE__, :get_total_cost)
  end

  def generate_report do
    GenServer.call(__MODULE__, :generate_report)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Load previous costs if file exists
    state =
      case File.read(@cost_file) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} ->
              %{
                total_cost: Map.get(data, "total_cost", 0.0),
                test_costs: Map.get(data, "test_costs", %{}),
                current_test: nil,
                request_log: []
              }

            _ ->
              initial_state()
          end

        _ ->
          initial_state()
      end

    {:ok, state}
  end

  @impl true
  def handle_cast({:track_request, provider, model, tokens, type}, state) do
    cost = calculate_cost(provider, model, tokens, type)

    updated_state =
      state
      |> update_in([:total_cost], &(&1 + cost))
      |> update_in(
        [:request_log],
        &[
          %{
            provider: provider,
            model: model,
            tokens: tokens,
            type: type,
            cost: cost,
            timestamp: DateTime.utc_now()
          }
          | &1
        ]
      )

    # Update current test cost if one is active
    updated_state =
      if state.current_test do
        update_in(updated_state, [:test_costs, state.current_test], &((&1 || 0.0) + cost))
      else
        updated_state
      end

    # Check total budget
    if updated_state.total_cost > @total_budget_limit do
      Logger.error(
        "TOTAL BUDGET EXCEEDED: $#{Float.round(updated_state.total_cost, 2)} > $#{@total_budget_limit}"
      )

      save_costs(updated_state)
      raise "Total test budget exceeded! Spent: $#{Float.round(updated_state.total_cost, 2)}"
    end

    # Save periodically
    if rem(length(updated_state.request_log), 10) == 0 do
      save_costs(updated_state)
    end

    {:noreply, updated_state}
  end

  @impl true
  def handle_call({:check_test_budget, test_name, limit}, _from, state) do
    current_cost = Map.get(state.test_costs, test_name, 0.0)

    if current_cost > limit do
      {:reply, {:error, :budget_exceeded, current_cost}, state}
    else
      # Set current test for tracking
      {:reply, :ok, %{state | current_test: test_name}}
    end
  end

  @impl true
  def handle_call({:get_test_cost, test_name}, _from, state) do
    cost = Map.get(state.test_costs, test_name, 0.0)
    {:reply, cost, state}
  end

  @impl true
  def handle_call(:get_total_cost, _from, state) do
    {:reply, state.total_cost, state}
  end

  @impl true
  def handle_call(:generate_report, _from, state) do
    report = %{
      total_cost: Float.round(state.total_cost, 2),
      total_requests: length(state.request_log),
      test_count: map_size(state.test_costs),
      top_expensive_tests:
        state.test_costs
        |> Enum.sort_by(fn {_, cost} -> -cost end)
        |> Enum.take(10)
        |> Enum.map(fn {test, cost} ->
          %{test: test, cost: Float.round(cost, 2)}
        end),
      cost_by_provider:
        Enum.reduce(state.request_log, %{}, fn req, acc ->
          Map.update(acc, req.provider, req.cost, &(&1 + req.cost))
        end)
        |> Enum.map(fn {provider, cost} ->
          %{provider: provider, cost: Float.round(cost, 2)}
        end)
    }

    {:reply, report, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, initial_state()}
  end

  # Helper Functions

  defp initial_state do
    %{
      total_cost: 0.0,
      test_costs: %{},
      current_test: nil,
      request_log: []
    }
  end

  defp calculate_cost(provider, model, tokens, type) do
    # Simplified cost calculation - expand as needed
    # Costs in dollars per 1K tokens
    costs = %{
      openai: %{
        "gpt-4" => %{input: 0.03, output: 0.06},
        "gpt-4-turbo" => %{input: 0.01, output: 0.03},
        "gpt-3.5-turbo" => %{input: 0.0005, output: 0.0015}
      },
      anthropic: %{
        "claude-3-opus" => %{input: 0.015, output: 0.075},
        "claude-3-sonnet" => %{input: 0.003, output: 0.015},
        "claude-3-haiku" => %{input: 0.00025, output: 0.00125}
      },
      gemini: %{
        "gemini-2.0-flash" => %{input: 0.00025, output: 0.0005},
        "gemini-2.5-flash" => %{input: 0.00025, output: 0.0005},
        "gemini-2.5-pro" => %{input: 0.0025, output: 0.005}
      }
    }

    provider_costs = Map.get(costs, provider, %{})
    model_costs = Map.get(provider_costs, model, %{input: 0.001, output: 0.002})

    rate =
      case type do
        :input -> model_costs.input
        :output -> model_costs.output
        _ -> (model_costs.input + model_costs.output) / 2
      end

    # Calculate cost for tokens
    tokens / 1000.0 * rate
  end

  defp save_costs(state) do
    data = %{
      "total_cost" => state.total_cost,
      "test_costs" => state.test_costs,
      "last_updated" => DateTime.utc_now()
    }

    File.write!(@cost_file, Jason.encode!(data, pretty: true))
  end
end
