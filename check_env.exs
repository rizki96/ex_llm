#!/usr/bin/env elixir

IO.puts "Mix environment: #{Mix.env()}"
IO.puts "Test environment?: #{Mix.env() == :test}"

# Check test cache config
config = ExLLM.TestCacheConfig.get_config()
IO.puts "\nTest Cache Config:"
IO.puts "  enabled: #{config.enabled}"
IO.puts "  auto_detect: #{config.auto_detect}"
IO.puts "  cache_dir: #{config.cache_dir}"
IO.puts "  cache_integration_tests: #{config.cache_integration_tests}"

# Check if we should be caching
IO.puts "\nCache Detection:"
IO.puts "  should_cache_responses?: #{ExLLM.TestCacheDetector.should_cache_responses?()}"

# Set test context manually
ExLLM.TestCacheDetector.set_test_context(%{
  module: CacheVerificationTest,
  test_name: "verify_caching_works",
  tags: [:integration],
  pid: self()
})

IO.puts "  should_cache_responses? (with context): #{ExLLM.TestCacheDetector.should_cache_responses?()}"