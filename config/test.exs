import Config

# Configure ExLLM for testing using centralized configuration
#
# The centralized config provides consistent test settings across
# all test environments and helpers.

# Note: This is loaded early before the Testing.Config module is available,
# so we define minimal config here and let test_helper.exs apply the full config
config :ex_llm,
  cache_strategy: ExLLM.Cache.Strategies.Test,
  env: :test
