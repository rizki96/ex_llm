import Config

# Configure ExLLM for testing
#
# Use the Test cache strategy, which allows test-specific caching behavior
# (e.g., for live API calls) while falling back to the production cache
# for regular unit tests.
config :ex_llm,
  cache_strategy: ExLLM.Cache.Strategies.Test
