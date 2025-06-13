defmodule ExLLM.Gemini.Tuning do
  @moduledoc """
  Google Gemini Fine-tuning API implementation.
  
  This module provides functionality for creating and managing tuned models
  using the Gemini API.
  """

  alias ExLLM.Config
  alias ExLLM.Gemini.Base

  # Request/Response structs

  defmodule TuningExample do
    @moduledoc """
    A single example for tuning.
    """
    defstruct [:text_input, :output]

    @type t :: %__MODULE__{
      text_input: String.t(),
      output: String.t()
    }

    def to_json(%__MODULE__{} = example) do
      %{
        "textInput" => example.text_input,
        "output" => example.output
      }
    end
  end

  defmodule TuningExamples do
    @moduledoc """
    A set of tuning examples.
    """
    defstruct [:examples]

    @type t :: %__MODULE__{
      examples: [TuningExample.t()]
    }

    def to_json(%__MODULE__{} = examples) do
      %{
        "examples" => Enum.map(examples.examples, &TuningExample.to_json/1)
      }
    end
  end

  defmodule Dataset do
    @moduledoc """
    Dataset for training or validation.
    """
    defstruct [:examples]

    @type t :: %__MODULE__{
      examples: TuningExamples.t() | nil
    }

    def to_json(%__MODULE__{} = dataset) do
      if dataset.examples do
        %{"examples" => TuningExamples.to_json(dataset.examples)}
      else
        %{}
      end
    end
  end

  defmodule Hyperparameters do
    @moduledoc """
    Hyperparameters controlling the tuning process.
    """
    defstruct [
      :learning_rate,
      :learning_rate_multiplier,
      :epoch_count,
      :batch_size
    ]

    @type t :: %__MODULE__{
      learning_rate: float() | nil,
      learning_rate_multiplier: float() | nil,
      epoch_count: integer() | nil,
      batch_size: integer() | nil
    }

    def to_json(%__MODULE__{} = params) do
      json = %{}
      
      json = if params.learning_rate do
        Map.put(json, "learningRate", params.learning_rate)
      else
        json
      end
      
      json = if params.learning_rate_multiplier do
        Map.put(json, "learningRateMultiplier", params.learning_rate_multiplier)
      else
        json
      end
      
      json = if params.epoch_count do
        Map.put(json, "epochCount", params.epoch_count)
      else
        json
      end
      
      if params.batch_size do
        Map.put(json, "batchSize", params.batch_size)
      else
        json
      end
    end
  end

  defmodule TuningSnapshot do
    @moduledoc """
    Record for a single tuning step.
    """
    defstruct [:step, :epoch, :mean_loss, :compute_time]

    @type t :: %__MODULE__{
      step: integer(),
      epoch: integer(),
      mean_loss: float(),
      compute_time: String.t()
    }

    def from_json(json) do
      %__MODULE__{
        step: json["step"],
        epoch: json["epoch"],
        mean_loss: json["meanLoss"],
        compute_time: json["computeTime"]
      }
    end
  end

  defmodule TuningTask do
    @moduledoc """
    Tuning task that creates tuned models.
    """
    defstruct [
      :start_time,
      :complete_time,
      :snapshots,
      :training_data,
      :hyperparameters
    ]

    @type t :: %__MODULE__{
      start_time: String.t() | nil,
      complete_time: String.t() | nil,
      snapshots: [TuningSnapshot.t()] | nil,
      training_data: Dataset.t(),
      hyperparameters: Hyperparameters.t() | nil
    }

    def to_json(%__MODULE__{} = task) do
      json = %{
        "trainingData" => Dataset.to_json(task.training_data)
      }
      
      if task.hyperparameters do
        Map.put(json, "hyperparameters", Hyperparameters.to_json(task.hyperparameters))
      else
        json
      end
    end

    def from_json(json) do
      %__MODULE__{
        start_time: json["startTime"],
        complete_time: json["completeTime"],
        snapshots: parse_snapshots(json["snapshots"]),
        training_data: parse_training_data(json["trainingData"]),
        hyperparameters: parse_hyperparameters(json["hyperparameters"])
      }
    end

    defp parse_snapshots(nil), do: []
    defp parse_snapshots(snapshots) do
      Enum.map(snapshots, &TuningSnapshot.from_json/1)
    end

    defp parse_training_data(nil), do: %Dataset{}
    defp parse_training_data(data) do
      %Dataset{
        examples: parse_examples(data["examples"])
      }
    end

    defp parse_examples(nil), do: nil
    defp parse_examples(data) do
      %TuningExamples{
        examples: Enum.map(data["examples"] || [], fn ex ->
          %TuningExample{
            text_input: ex["textInput"],
            output: ex["output"]
          }
        end)
      }
    end

    defp parse_hyperparameters(nil), do: nil
    defp parse_hyperparameters(data) do
      %Hyperparameters{
        learning_rate: data["learningRate"],
        learning_rate_multiplier: data["learningRateMultiplier"],
        epoch_count: data["epochCount"],
        batch_size: data["batchSize"]
      }
    end
  end

  defmodule TunedModelSource do
    @moduledoc """
    Tuned model as a source for training a new model.
    """
    defstruct [:tuned_model, :base_model]

    @type t :: %__MODULE__{
      tuned_model: String.t(),
      base_model: String.t() | nil
    }

    def from_json(json) do
      %__MODULE__{
        tuned_model: json["tunedModel"],
        base_model: json["baseModel"]
      }
    end
  end

  defmodule TunedModel do
    @moduledoc """
    A fine-tuned model created using the tuning API.
    """
    defstruct [
      :name,
      :display_name,
      :description,
      :state,
      :create_time,
      :update_time,
      :tuning_task,
      :reader_project_numbers,
      :tuned_model_source,
      :base_model,
      :temperature,
      :top_p,
      :top_k
    ]

    @type state :: :STATE_UNSPECIFIED | :CREATING | :ACTIVE | :FAILED

    @type t :: %__MODULE__{
      name: String.t() | nil,
      display_name: String.t() | nil,
      description: String.t() | nil,
      state: state() | nil,
      create_time: String.t() | nil,
      update_time: String.t() | nil,
      tuning_task: TuningTask.t() | nil,
      reader_project_numbers: [String.t()] | nil,
      tuned_model_source: TunedModelSource.t() | nil,
      base_model: String.t() | nil,
      temperature: float() | nil,
      top_p: float() | nil,
      top_k: integer() | nil
    }

    def from_json(json) do
      %__MODULE__{
        name: json["name"],
        display_name: json["displayName"],
        description: json["description"],
        state: parse_state(json["state"]),
        create_time: json["createTime"],
        update_time: json["updateTime"],
        tuning_task: parse_tuning_task(json["tuningTask"]),
        reader_project_numbers: json["readerProjectNumbers"],
        tuned_model_source: parse_tuned_model_source(json["tunedModelSource"]),
        base_model: json["baseModel"],
        temperature: json["temperature"],
        top_p: json["topP"],
        top_k: json["topK"]
      }
    end

    defp parse_state(nil), do: nil
    defp parse_state("STATE_UNSPECIFIED"), do: :STATE_UNSPECIFIED
    defp parse_state("CREATING"), do: :CREATING
    defp parse_state("ACTIVE"), do: :ACTIVE
    defp parse_state("FAILED"), do: :FAILED
    defp parse_state(_), do: :STATE_UNSPECIFIED

    defp parse_tuning_task(nil), do: nil
    defp parse_tuning_task(json), do: TuningTask.from_json(json)

    defp parse_tuned_model_source(nil), do: nil
    defp parse_tuned_model_source(json), do: TunedModelSource.from_json(json)
  end

  defmodule ListTunedModelsResponse do
    @moduledoc """
    Response from listing tuned models.
    """
    defstruct [:tuned_models, :next_page_token]

    @type t :: %__MODULE__{
      tuned_models: [TunedModel.t()],
      next_page_token: String.t() | nil
    }

    def from_json(json) do
      %__MODULE__{
        tuned_models: Enum.map(json["tunedModels"] || [], &TunedModel.from_json/1),
        next_page_token: json["nextPageToken"]
      }
    end
  end

  # API Functions

  @type options :: [
    {:api_key, String.t()} |
    {:config_provider, module()} |
    {:page_size, integer()} |
    {:page_token, String.t()} |
    {:filter, String.t()} |
    {:tuned_model_id, String.t()} |
    {:update_mask, String.t()} |
    {:timeout, integer()}
  ]

  @doc """
  Creates a tuned model.
  
  ## Parameters
  
  * `request` - The tuned model creation request containing:
    * `:base_model` - The base model to tune (required)
    * `:tuning_task` - The tuning task configuration (required)
    * `:display_name` - Optional display name
    * `:description` - Optional description
    * `:temperature` - Optional temperature setting
    * `:top_p` - Optional nucleus sampling parameter
    * `:top_k` - Optional top-k sampling parameter
  * `opts` - Options including:
    * `:api_key` - Google API key
    * `:tuned_model_id` - Optional custom ID for the tuned model
  
  ## Returns
  
  * `{:ok, operation}` - The long-running operation for tracking tuning progress
  * `{:error, reason}` - Error details
  """
  @spec create_tuned_model(map(), options()) :: {:ok, map()} | {:error, term()}
  def create_tuned_model(request, opts \\ []) do
    with :ok <- validate_create_request(request),
         body <- create_request_body(request),
         api_key <- get_api_key(opts),
         query_params <- build_create_query_params(opts) do
      
      Base.request(
        method: :post,
        url: "/tunedModels",
        body: body,
        query: query_params,
        api_key: api_key,
        opts: opts
      )
    end
  end

  @doc """
  Lists tuned models.
  
  ## Parameters
  
  * `opts` - Options including:
    * `:api_key` - Google API key
    * `:page_size` - Maximum number of models to return
    * `:page_token` - Token for pagination
    * `:filter` - Filter expression
  
  ## Returns
  
  * `{:ok, response}` - List of tuned models
  * `{:error, reason}` - Error details
  """
  @spec list_tuned_models(options()) :: {:ok, ListTunedModelsResponse.t()} | {:error, term()}
  def list_tuned_models(opts \\ []) do
    api_key = get_api_key(opts)
    query_params = build_list_query_params(opts)
    
    case Base.request(
      method: :get,
      url: "/tunedModels",
      query: query_params,
      api_key: api_key,
      opts: opts
    ) do
      {:ok, json} -> {:ok, ListTunedModelsResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Gets information about a specific tuned model.
  
  ## Parameters
  
  * `name` - The resource name of the model (e.g., "tunedModels/my-model-id")
  * `opts` - Options including `:api_key`
  
  ## Returns
  
  * `{:ok, model}` - The tuned model details
  * `{:error, reason}` - Error details
  """
  @spec get_tuned_model(String.t(), options()) :: {:ok, TunedModel.t()} | {:error, term()}
  def get_tuned_model(name, opts \\ []) do
    api_key = get_api_key(opts)
    
    case Base.request(
      method: :get,
      url: "/#{name}",
      api_key: api_key,
      opts: opts
    ) do
      {:ok, json} -> {:ok, TunedModel.from_json(json)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Updates a tuned model.
  
  ## Parameters
  
  * `name` - The resource name of the model
  * `update` - Map of fields to update
  * `opts` - Options including:
    * `:api_key` - Google API key
    * `:update_mask` - Field mask specifying which fields to update
  
  ## Returns
  
  * `{:ok, model}` - The updated model
  * `{:error, reason}` - Error details
  """
  @spec update_tuned_model(String.t(), map(), options()) :: {:ok, TunedModel.t()} | {:error, term()}
  def update_tuned_model(name, update, opts \\ []) do
    with :ok <- validate_update_request(update),
         body <- update_request_body(update, opts[:update_mask]),
         api_key <- get_api_key(opts),
         query_params <- build_update_query_params(opts) do
      
      case Base.request(
        method: :patch,
        url: "/#{name}",
        body: body,
        query: query_params,
        api_key: api_key,
        opts: opts
      ) do
        {:ok, json} -> {:ok, TunedModel.from_json(json)}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Deletes a tuned model.
  
  ## Parameters
  
  * `name` - The resource name of the model
  * `opts` - Options including `:api_key`
  
  ## Returns
  
  * `{:ok, %{}}` - Empty response on success
  * `{:error, reason}` - Error details
  """
  @spec delete_tuned_model(String.t(), options()) :: {:ok, map()} | {:error, term()}
  def delete_tuned_model(name, opts \\ []) do
    api_key = get_api_key(opts)
    
    Base.request(
      method: :delete,
      url: "/#{name}",
      api_key: api_key,
      opts: opts
    )
  end

  @doc """
  Generates content using a tuned model.
  
  ## Parameters
  
  * `model` - The tuned model name (e.g., "tunedModels/my-model")
  * `request` - The generation request
  * `opts` - Options including `:api_key`
  
  ## Returns
  
  * `{:ok, response}` - The generation response
  * `{:error, reason}` - Error details
  """
  @spec generate_content(String.t(), map(), options()) :: {:ok, map()} | {:error, term()}
  def generate_content(model, request, opts \\ []) do
    api_key = get_api_key(opts)
    
    Base.request(
      method: :post,
      url: "/#{model}:generateContent",
      body: request,
      api_key: api_key,
      opts: opts
    )
  end

  @doc """
  Streams content generation using a tuned model.
  
  ## Parameters
  
  * `model` - The tuned model name
  * `request` - The generation request
  * `opts` - Options including `:api_key`
  
  ## Returns
  
  * `{:ok, stream}` - Stream of response chunks
  * `{:error, reason}` - Error details
  """
  @spec stream_generate_content(String.t(), map(), options()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_generate_content(model, request, opts \\ []) do
    api_key = get_api_key(opts)
    
    Base.stream_request(
      method: :post,
      url: "/#{model}:streamGenerateContent",
      body: request,
      api_key: api_key,
      opts: opts
    )
  end

  @doc """
  Waits for a tuning operation to complete.
  
  ## Parameters
  
  * `operation_name` - The operation name from create_tuned_model
  * `opts` - Options including:
    * `:api_key` - Google API key
    * `:timeout` - Maximum time to wait in milliseconds (default: 300_000)
  
  ## Returns
  
  * `{:ok, model}` - The completed tuned model
  * `{:error, reason}` - Error details
  """
  @spec wait_for_tuning(String.t(), options()) :: {:ok, TunedModel.t()} | {:error, term()}
  def wait_for_tuning(_operation_name, _opts \\ []) do
    # This would poll the operation status until completion
    # For now, returning a placeholder
    {:error, :not_implemented}
  end

  # Validation functions

  @doc false
  def validate_create_request(request) do
    cond do
      !request[:base_model] ->
        {:error, "base_model is required"}
      
      !request[:tuning_task] ->
        {:error, "tuning_task is required"}
      
      !request[:tuning_task][:training_data] || !request[:tuning_task][:training_data][:examples] ->
        {:error, "training_data with examples is required"}
      
      true ->
        # Handle both struct and map cases
        examples_data = request[:tuning_task][:training_data][:examples]
        examples_list = case examples_data do
          %TuningExamples{examples: list} -> list
          %{examples: list} -> list
          _ -> []
        end
        
        if length(examples_list) == 0 do
          {:error, "training_data must contain at least one example"}
        else
          :ok
        end
    end
  end

  @doc false
  def validate_update_request(update) do
    cond do
      update[:temperature] && (update[:temperature] < 0.0 || update[:temperature] > 1.0) ->
        {:error, "temperature must be between 0.0 and 1.0"}
      
      update[:top_p] && (update[:top_p] < 0.0 || update[:top_p] > 1.0) ->
        {:error, "top_p must be between 0.0 and 1.0"}
      
      true ->
        :ok
    end
  end

  # Helper functions

  @doc false
  def create_request_body(request) do
    body = %{}
    
    body = if request[:display_name] do
      Map.put(body, "displayName", request[:display_name])
    else
      body
    end
    
    body = if request[:description] do
      Map.put(body, "description", request[:description])
    else
      body
    end
    
    body = Map.put(body, "baseModel", request[:base_model])
    
    body = if request[:tuning_task] do
      task = request[:tuning_task]
      tuning_task_json = TuningTask.to_json(%TuningTask{
        training_data: %Dataset{
          examples: task[:training_data][:examples]
        },
        hyperparameters: if task[:hyperparameters] do
          # Convert map to struct if it's a map
          case task[:hyperparameters] do
            %Hyperparameters{} = h -> h
            map when is_map(map) -> 
              %Hyperparameters{
                learning_rate: map[:learning_rate],
                learning_rate_multiplier: map[:learning_rate_multiplier],
                epoch_count: map[:epoch_count],
                batch_size: map[:batch_size]
              }
            _ -> nil
          end
        end
      })
      Map.put(body, "tuningTask", tuning_task_json)
    else
      body
    end
    
    body = if request[:temperature] do
      Map.put(body, "temperature", request[:temperature])
    else
      body
    end
    
    body = if request[:top_p] do
      Map.put(body, "topP", request[:top_p])
    else
      body
    end
    
    body = if request[:top_k] do
      Map.put(body, "topK", request[:top_k])
    else
      body
    end
    
    body = if request[:reader_project_numbers] do
      Map.put(body, "readerProjectNumbers", request[:reader_project_numbers])
    else
      body
    end
    
    body
  end

  @doc false
  def update_request_body(update, update_mask) do
    body = %{}
    
    # If update_mask is provided, only include fields in the mask
    fields = if update_mask do
      String.split(update_mask, ",")
    else
      Map.keys(update)
    end
    
    Enum.reduce(fields, body, fn field, acc ->
      case field do
        "displayName" when is_map_key(update, :display_name) ->
          Map.put(acc, "displayName", update[:display_name])
        
        "description" when is_map_key(update, :description) ->
          Map.put(acc, "description", update[:description])
        
        "temperature" when is_map_key(update, :temperature) ->
          Map.put(acc, "temperature", update[:temperature])
        
        "topP" when is_map_key(update, :top_p) ->
          Map.put(acc, "topP", update[:top_p])
        
        "topK" when is_map_key(update, :top_k) ->
          Map.put(acc, "topK", update[:top_k])
        
        _ ->
          # Handle direct field names if no mask
          if !update_mask do
            case field do
              :display_name -> Map.put(acc, "displayName", update[:display_name])
              :description -> Map.put(acc, "description", update[:description])
              :temperature -> Map.put(acc, "temperature", update[:temperature])
              :top_p -> Map.put(acc, "topP", update[:top_p])
              :top_k -> Map.put(acc, "topK", update[:top_k])
              _ -> acc
            end
          else
            acc
          end
      end
    end)
  end

  defp get_api_key(opts) do
    config_provider = opts[:config_provider] || Config.DefaultProvider
    opts[:api_key] || config_provider.get_config(:gemini)[:api_key]
  end

  defp build_create_query_params(opts) do
    params = %{}
    
    if opts[:tuned_model_id] do
      Map.put(params, "tunedModelId", opts[:tuned_model_id])
    else
      params
    end
  end

  defp build_list_query_params(opts) do
    params = %{}
    
    params = if opts[:page_size] do
      Map.put(params, "pageSize", opts[:page_size])
    else
      params
    end
    
    params = if opts[:page_token] do
      Map.put(params, "pageToken", opts[:page_token])
    else
      params
    end
    
    if opts[:filter] do
      Map.put(params, "filter", opts[:filter])
    else
      params
    end
  end

  defp build_update_query_params(opts) do
    params = %{}
    
    if opts[:update_mask] do
      Map.put(params, "updateMask", opts[:update_mask])
    else
      params
    end
  end
end