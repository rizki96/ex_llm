# Check for OAuth2 tokens and exclude OAuth2 tests if not available
oauth2_available = File.exists?(".gemini_tokens")

exclude_tags = [:integration, :oauth2]

if not oauth2_available do
  IO.puts("\n⚠️  OAuth2 tests excluded - no .gemini_tokens file found")
  IO.puts("   Run: elixir scripts/setup_oauth2.exs to enable OAuth2 tests\n")
end

ExUnit.start(exclude: exclude_tags)

# Compile test support files
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/gemini_oauth2_test_helper.ex", __DIR__)
Code.require_file("support/config_provider_helper.ex", __DIR__)
