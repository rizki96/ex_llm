# Fine-tuning tutorial

This tutorial will help you get started with the Gemini API tuning service using either the Python SDK or the REST API using `curl`. The examples show how to tune the text model behind the Gemini API text generation service.

## Before you begin

Before calling the Gemini API, ensure you have [your SDK of choice](https://www.google.com/search?q=https://ai.google.dev/tutorials/python_quickstart%23setup) installed, and a [Gemini API key](https://www.google.com/search?q=https://ai.google.dev/tutorials/rest_quickstart%23get_an_api_key) configured and ready to use.

[Try a Colab notebook](https://www.google.com/search?q=https://colab.research.google.com/github/google/generative-ai-docs/blob/main/site/en/tutorials/model_tuning.ipynb) [View notebook on GitHub](https://www.google.com/search?q=https://github.com/google/generative-ai-docs/blob/main/site/en/tutorials/model_tuning.ipynb)

## Limitations

Before tuning a model, you should be aware of the following limitations:

### Fine-tuning datasets

Fine-tuning datasets for Gemini 1.5 Flash have the following limitations:

  * The maximum input size per example is 40,000 characters.
  * The maximum output size per example is 5,000 characters.
  * Only input-output pair examples are supported. Chat-style multi-turn conversations are not supported.

### Tuned models

Tuned models have the following limitations:

  * The input limit of a tuned Gemini 1.5 Flash model is 40,000 characters.
  * JSON mode is not supported with tuned models.
  * Only text input is supported.

## List tuned models

You can check your existing tuned models with the `tunedModels.list` method.

```bash
# Sending a page_size is optional
curl -X GET https://generativelanguage.googleapis.com/v1beta/tunedModels?page_size=5 \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${access_token}" \
    -H "x-goog-user-project: ${project_id}" > tuned_models.json

jq .tunedModels[].name < tuned_models.json

# Send the nextPageToken to get the next page.
page_token=$(jq .nextPageToken < tuned_models.json | tr -d '"')
if [[ "$page_token" != "null"" ]]; then
curl -X GET https://generativelanguage.googleapis.com/v1beta/tunedModels?page_size=5\&page_token=${page_token}?key=$GEMINI_API_KEY \
    -H "Content-Type: application/json"  > tuned_models2.json

jq .tunedModels[].name < tuned_models.json
fi
```

## Create a tuned model

To create a tuned model, you need to pass your dataset to the model in the `tunedModels.create` method.

For this example, you will tune a model to generate the next number in the sequence. For example, if the input is `1`, the model should output `2`. If the input is `one hundred`, the output should be `one hundred one`.

```bash
curl -X POST "https://generativelanguage.googleapis.com/v1beta/tunedModels?key=$GEMINI_API_KEY" \
    -H 'Content-Type: application/json' \
    -d '
      {
        "display_name": "number generator model",
        "base_model": "models/gemini-1.5-flash-001-tuning",
        "tuning_task": {
          "hyperparameters": {
            "batch_size": 2,
            "learning_rate": 0.001,
            "epoch_count":5,
          },
          "training_data": {
            "examples": {
              "examples": [
                {
                    "text_input": "1",
                    "output": "2",
                },{
                    "text_input": "3",
                    "output": "4",
                },{
                    "text_input": "-3",
                    "output": "-2",
                },{
                    "text_input": "twenty two",
                    "output": "twenty three",
                },{
                    "text_input": "two hundred",
                    "output": "two hundred one",
                },{
                    "text_input": "ninety nine",
                    "output": "one hundred",
                },{
                    "text_input": "8",
                    "output": "9",
                },{
                    "text_input": "-98",
                    "output": "-97",
                },{
                    "text_input": "1,000",
                    "output": "1,001",
                },{
                    "text_input": "10,100,000",
                    "output": "10,100,001",
                },{
                    "text_input": "thirteen",
                    "output": "fourteen",
                },{
                    "text_input": "eighty",
                    "output": "eighty one",
                },{
                    "text_input": "one",
                    "output": "two",
                },{
                    "text_input": "three",
                    "output": "four",
                },{
                    "text_input": "seven",
                    "output": "eight",
                }
              ]
            }
          }
        }
      }' | tee tunemodel.json

# Check the operation for status updates during training.
# Note: you can only check the operation on v1/
operation=$(cat tunemodel.json | jq ".name" | tr -d '"')
tuning_done=false
while [[ "$tuning_done" != "true" ]];do
  sleep 5
  curl -X GET "https://generativelanguage.googleapis.com/v1/${operation}?key=$GEMINI_API_KEY" \
    -H 'Content-Type: application/json' \
     2> /dev/null > tuning_operation.json
  complete=$(jq .metadata.completedPercent < tuning_operation.json)
  tput cuu1
  tput el
  echo "Tuning...${complete}%"
  tuning_done=$(jq .done < tuning_operation.json)
done

# Or get the TunedModel and check it's state. The model is ready to use if the state is active.
modelname=$(cat tunemodel.json | jq ".metadata.tunedModel" | tr -d '"')

curl -X GET  https://generativelanguage.googleapis.com/v1beta/${modelname}?key=$GEMINI_API_KEY \
    -H 'Content-Type: application/json' > tuned_model.json

cat tuned_model.json | jq ".state"
```

The optimal values for epoch count, batch size, and learning rate are dependent on your dataset and other constraints of your use case. To learn more about these values, see [Advanced tuning settings](https://www.google.com/search?q=https://ai.google.dev/gemini/tuning/tuned_models%23advanced_settings) and [Hyperparameters](https://www.google.com/search?q=https://ai.google.dev/gemini/tuning/tuned_models%23hyperparameters).

Tip: For a more general introduction to these hyperparameters, see [Linear regression: Hyperparameters](https://developers.google.com/machine-learning/crash-course/linear-regression/hyperparameters) in the [Machine Learning Crash Course](https://developers.google.com/machine-learning/crash-course/).

Your tuned model is immediately added to the list of tuned models, but its state is set to "creating" while the model is tuned.

## Try the model

You can use the `tunedModels.generateContent` method and specify the name of the tuned model to test its performance.

```bash
curl -X POST https://generativelanguage.googleapis.com/v1beta/$modelname:generateContent?key=$GEMINI_API_KEY \
    -H 'Content-Type: application/json' \
    -d '{        "contents": [{        "parts": [{          "text": "LXIII"          }]        }]        }' 2> /dev/null
```

## Delete the model

You can clean up your tuned model list by deleting models you no longer need. Use the `tunedModels.delete` method to delete a model. If you canceled any tuning jobs, you may want to delete those as their performance may be unpredictable.

```bash
curl -X DELETE https://generativelanguage.googleapis.com/v1beta/${modelname}?key=$GEMINI_API_KEY \
    -H 'Content-Type: application/json'
```
