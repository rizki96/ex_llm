# Generate video using Veo

The Gemini API provides access to Veo 2, Google's most capable video generation model to date. Veo generates videos in a wide range of cinematic and visual styles, capturing prompt nuance to render intricate details consistently across frames. This guide will help you get started with Veo using the Gemini API.
For video prompting guidance, check out the [Veo prompt guide](https://www.google.com/search?q=%23veo-prompt-guide) section.

**Note:** Veo is a paid feature and will not run in the Free tier. Visit the [Pricing] page for more details.

## Before you begin

Before calling the Gemini API, ensure you have your [SDK of choice] installed, and a [Gemini API key] configured and ready to use.
To use Veo with the Google Gen AI SDKs, ensure that you have one of the following versions installed:

  * Python v1.10.0 or later
  * TypeScript and JavaScript v0.8.0 or later
  * Go v1.0.0 or later

## Generate videos

This section provides code examples for generating videos using [text prompts](https://www.google.com/search?q=%23generate-from-text) and [using images](https://www.google.com/search?q=%23generate-from-images).

### Generate from text

You can use the following code to generate videos with Veo:

(Code examples for Python, JavaScript, Go, and REST are present in the original text and are omitted here for brevity as per instructions)

This code takes about 2-3 minutes to run, though it may take longer if resources are constrained. If you see an error message instead of a video, this means that resources are constrained and your request couldn't be completed. In this case, run the code again.

Generated videos are stored on the server for 2 days, after which they are removed. If you want to save a local copy of your generated video, you must run `result()` and `save()` within 2 days of generation.

### Generate from images

You can also generate videos using images. The following code generates an image using Imagen, then uses the generated image as the starting frame for the generated video.

First, generate an image using [Imagen]:

(Code examples for Python, JavaScript, and Go are present in the original text and are omitted here for brevity as per instructions)

Then, generate a video using the resulting image as the first frame:

(Code examples for Python, JavaScript, and Go are present in the original text and are omitted here for brevity as per instructions)

### Veo model parameters

(Naming conventions vary by programming language.)

  * `prompt`: The text prompt for the video. When present, the `image` parameter is optional.
  * `image`: The image to use as the first frame for the video. When present, the `prompt` parameter is optional.
  * `negativePrompt`: Text string that describes anything you want to discourage the model from generating.
  * `aspectRatio`: Changes the aspect ratio of the generated video. Supported values are `"16:9"` and `"9:16"`. The default is `"16:9"`.
  * `personGeneration`: Allow the model to generate videos of people. The following values are supported:
      * Text-to-video generation:
          * `"dont_allow"`: Don't allow the inclusion of people or faces.
          * `"allow_adult"`: Generate videos that include adults, but not children.
      * Image-to-video generation:
          * `"dont_allow"`: Don't allow the inclusion of people or faces.
          * `"allow_adult"`: Generate videos that include adults, but not children.
            See [Limitations](https://www.google.com/search?q=%23limitations).
  * `numberOfVideos`: Output videos requested, either `1` or `2`.
  * `durationSeconds`: Length of each output video in seconds, between `5` and `8`.
  * `enhance_prompt`: Enable or disable the prompt rewriter. Enabled by default.

### Specifications

  * Modalities
      * Text-to-video generation
      * Image-to-video generation
  * Request latency
      * Min: 11 seconds
      * Max: 6 minutes (during peak hours)
  * Variable length generation 5-8 seconds
  * Resolution 720p
  * Frame rate 24fps
  * Aspect ratio
      * 16:9 - landscape
      * 9:16 - portrait
  * Input languages (text-to-video) English

### Limitations

  * Image-to-video `personGeneration` is not allowed in EU, UK, CH, MENA locations

**Note:** Check out the [Models], [Pricing], and [Rate limits] pages for more usage limitations for Veo.

Videos created by Veo are watermarked using [SynthID], our tool for watermarking and identifying AI-generated content, and are passed through safety filters and memorization checking processes that help mitigate privacy, copyright and bias risks.

## Things to try

To get the most out of Veo, incorporate video-specific terminology into your prompts. Veo understands a wide range of terms related to:

  * **Shot composition:** Specify the framing and number of subjects in the shot (e.g., "single shot," "two shot," "over-the-shoulder shot").
  * **Camera positioning and movement:** Control the camera's location and movement using terms like "eye level," "high angle," "worms eye," "dolly shot," "zoom shot," "pan shot," and "tracking shot."
  * **Focus and lens effects:** Use terms like "shallow focus," "deep focus," "soft focus," "macro lens," and "wide-angle lens" to achieve specific visual effects.
  * **Overall style and subject:** Guide Veo's creative direction by specifying styles like "sci-fi," "romantic comedy," "action movie," or "animation." You can also describe the subjects and backgrounds you want, such as "cityscape," "nature," "vehicles," or "animals."

## Veo prompt guide

This section of the Veo guide contains examples of videos you can create using Veo, and shows you how to modify prompts to produce distinct results.

### Safety filters

Veo applies safety filters across Gemini to help ensure that generated videos and uploaded photos don't contain offensive content. Prompts that violate our [terms and guidelines] are blocked.

### Prompt writing basics

Good prompts are descriptive and clear. To get your generated video as close as possible to what you want, start with identifying your core idea, and then refine your idea by adding keywords and modifiers.

The following elements should be included in your prompt:

  * **Subject:** The object, person, animal, or scenery that you want in your video.
  * **Context:** The background or context in which the subject is placed.
  * **Action:** What the subject is doing (for example, walking, running, or turning their head).
  * **Style:** This can be general or very specific. Consider using specific film style keywords, such as horror film, film noir, or animated styles like cartoon style.
  * **Camera motion:** \[Optional] What the camera is doing, such as aerial view, eye-level, top-down shot, or low-angle shot.
  * **Composition:** \[Optional] How the shot is framed, such as wide shot, close-up, or extreme close-up.
  * **Ambiance:** \[Optional] How the color and light contribute to the scene, such as blue tones, night, or warm tones.

### More tips for writing prompts

The following tips help you write prompts that generate your videos:

  * **Use descriptive language:** Use adjectives and adverbs to paint a clear picture for Veo.
  * **Provide context:** If necessary, include background information to help your model understand what you want.
  * **Reference specific artistic styles:** If you have a particular aesthetic in mind, reference specific artistic styles or art movements.
  * **Utilize prompt engineering tools:** Consider exploring prompt engineering tools or resources to help you refine your prompts and achieve optimal results. For more information, visit [Introduction to prompt design].
  * **Enhance the facial details in your personal and group images:** Specify facial details as a focus of the photo like using the word portrait in the prompt.

### Example prompts and output

This section presents several prompts, highlighting how descriptive details can elevate the outcome of each video.

#### Icicles

This video demonstrates how you can use the elements of [prompt writing basics](https://www.google.com/search?q=%23prompt-writing-basics) in your prompt.

| Prompt                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Generated output |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------- |
| Close up shot (composition) of melting icicles (subject) on a frozen rock wall (context) with cool blue tones (ambiance), zoomed in (camera motion) maintaining close-up detail of water drips (action). |                  |

#### Man on the phone

These videos demonstrate how you can revise your prompt with increasingly specific details to get Veo
