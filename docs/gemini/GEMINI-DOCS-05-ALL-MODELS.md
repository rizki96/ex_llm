# Gemini models

* **2.5 Pro** experiment
    Our most powerful thinking model with maximum response accuracy and state-of-the-art performance
    Input audio, images, video, and text, get text responses
    Tackle difficult problems, analyze large databases, and more
    Best for complex coding, reasoning, and multimodal understanding
* **2.5 Flash** experiment
    Our best model in terms of price-performance, offering well-rounded capabilities.
    Input audio, images, video, and text, and get text responses
    Model thinks as needed; or, you can configure a thinking budget
    Best for low latency, high volume tasks that require thinking
* **2.0 Flash** spark
    Our newest multimodal model, with next generation features and improved capabilities
    Input audio, images, video, and text, get text responses
    Generate code and images, extract data, analyze files, generate graphs, and more
    Low latency, enhanced performance, built to power agentic experiences

## Model variants

The Gemini API offers different models that are optimized for specific use cases. Here's a brief overview of Gemini variants that are available:

| Model variant                       | Input(s)                         | Output        | Optimized for                                                                   |
| :---------------------------------- | :------------------------------- | :------------ | :------------------------------------------------------------------------------ |
| Gemini 2.5 Flash Preview 04-17      | Audio, images, videos, and text  | Text          | Adaptive thinking, cost efficiency                                              |
| Gemini 2.5 Pro Preview              | Audio, images, videos, and text  | Text          | Enhanced thinking and reasoning, multimodal understanding, advanced coding, and more |
| Gemini 2.0 Flash                    | Audio, images, videos, and text  | Text          | Next generation features, speed.                                                |
| Gemini 2.0 Flash Preview Image Generation | Audio, images, videos, and text  | Text, images  | Conversational image generation and editing                                     |
| Gemini 2.0 Flash-Lite               | Audio, images, videos, and text  | Text          | Cost efficiency and low latency                                                 |
| Gemini 1.5 Flash                    | Audio, images, videos, and text  | Text          | Fast and versatile performance across a diverse variety of tasks                |
| Gemini 1.5 Flash-8B                 | Audio, images, videos, and text  | Text          | High volume and lower intelligence tasks                                        |
| Gemini 1.5 Pro                      | Audio, images, videos, and text  | Text          | Complex reasoning tasks requiring more intelligence                             |
| Gemini Embedding                    | Text                             | Text embeddings | Measuring the relatedness of text strings                                       |
| Imagen 3                            | Text                             | Images        | Our most advanced image generation model                                        |
| Veo 2                               | Text, images                     | Video         | High quality video generation                                                   |
| Gemini 2.0 Flash Live               | Audio, video, and text           | Text, audio   | Low-latency bidirectional voice and video interactions                            |

You can view the rate limits for each model on the [rate limits page].

See the [examples] to explore the capabilities of these model variations.

## Model version name patterns

Gemini models are available in either **stable**, **preview**, or **experimental** versions. In your code, you can use one of the following model name formats to specify which model and version you want to use.

### Latest stable

Points to the most recent stable version released for the specified model generation and variation.
To specify the latest stable version, use the following pattern: `<model>-<generation>-<variation>`. For example, `gemini-2.0-flash`.

### Stable

Points to a specific stable model. Stable models usually don't change. Most production apps should use a specific stable model.
To specify a stable version, use the following pattern: `<model>-<generation>-<variation>-<version>`. For example, `gemini-2.0-flash-001`.

### Preview

Points to a preview model which may not be suitable for production use, come with more restrictive rate limits, but may have billing enabled.
To specify a preview version, use the following pattern: `<model>-<generation>-<variation>-<version>`. For example, `gemini-2.5-pro-preview-05-06`.

### Experimental

Points to an experimental model which may not be suitable for production use and come with more restrictive rate limits. We release experimental models to gather feedback and get our latest updates into the hands of developers quickly.
To specify an experimental version, use the following pattern: `<model>-<generation>-<variation>-<version>`. For example, `gemini-2.0-pro-exp-02-05`.

## Experimental models

In addition to stable models, the Gemini API offers experimental models which may not be suitable for production use and come with more restrictive rate limits.
We release experimental models to gather feedback, get our latest updates into the hands of developers quickly, and highlight the pace of innovation happening at Google. What we learn from experimental launches informs how we release models more widely. An experimental model can be swapped for another without prior notice. We don't guarantee that an experimental model will become a stable model in the future.

### Previous experimental models

As new versions or stable releases become available, we remove and replace experimental models. You can find the previous experimental models we released in the following section along with the replacement version:

| Model code                                  | Base model                      | Replacement version                      |
| :------------------------------------------ | :------------------------------ | :--------------------------------------- |
| gemini-2.0-flash-exp-image-generation       | Gemini 2.0 Flash                | gemini-2.0-flash-preview-image-generation |
| gemini-2.5-pro-preview-03-25                | Gemini 2.5 Pro Preview          | gemini-2.5-pro-preview-05-06              |
| gemini-2.0-flash-thinking-exp-01-21         | Gemini 2.5 Flash                | gemini-2.5-flash-preview-04-17            |
| gemini-2.0-pro-exp-02-05                    | Gemini 2.0 Pro Experimental     | gemini-2.5-pro-preview-03-25              |
| gemini-2.0-flash-exp                        | Gemini 2.0 Flash                | gemini-2.0-flash                         |
| gemini-exp-1206                             | Gemini 2.0 Pro                  | gemini-2.0-pro-exp-02-05                  |
| gemini-2.0-flash-thinking-exp-1219          | Gemini 2.0 Flash Thinking       | gemini-2.0-flash-thinking-exp-01-21       |
| gemini-exp-1121                             | Gemini                          | gemini-exp-1206                          |
| gemini-exp-1114                             | Gemini                          | gemini-exp-1206                          |
| gemini-1.5-pro-exp-0827                     | Gemini 1.5 Pro                  | gemini-exp-1206                          |
| gemini-1.5-pro-exp-0801                     | Gemini 1.5 Pro                  | gemini-exp-1206                          |
| gemini-1.5-flash-8b-exp-0924                | Gemini 1.5 Flash-8B             | gemini-1.5-flash-8b                      |
| gemini-1.5-flash-8b-exp-0827                | Gemini 1.5 Flash-8B             | gemini-1.5-flash-8b                      |

## Supported languages

Gemini models are trained to work with the following languages:

* Arabic (ar)
* Bengali (bn)
* Bulgarian (bg)
* Chinese simplified and traditional (zh)
* Croatian (hr)
* Czech (cs)
* Danish (da)
* Dutch (nl)
* English (en)
* Estonian (et)
* Finnish (fi)
* French (fr)
* German (de)
* Greek (el)
* Hebrew (iw)
* Hindi (hi)
* Hungarian (hu)
* Indonesian (id)
* Italian (it)
* Japanese (ja)
* Korean (ko)
* Latvian (lv)
* Lithuanian (lt)
* Norwegian (no)
* Polish (pl)
* Portuguese (pt)
* Romanian (ro)
* Russian (ru)
* Serbian (sr)
* Slovak (sk)
* Slovenian (sl)
* Spanish (es)
* Swahili (sw)
* Swedish (sv)
* Thai (th)
* Turkish (tr)
* Ukrainian (uk)
* Vietnamese (vi)
