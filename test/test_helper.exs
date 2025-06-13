ExUnit.start(exclude: [:integration])

# Compile test support files
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/gemini_oauth2_test_helper.ex", __DIR__)
