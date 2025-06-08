ExUnit.start(exclude: [:integration])

# Compile test support files
Code.require_file("support/test_helpers.ex", __DIR__)
