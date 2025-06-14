defmodule ConditionalSkipExample do
  @moduledoc """
  Examples of how to conditionally skip tests in ExUnit.
  
  Since ExUnit doesn't support returning {:skip, reason} from setup callbacks,
  here are the recommended approaches.
  """
end

defmodule ConditionalSkipExampleTest do
  use ExUnit.Case

  # Option 1: Use module attributes with conditional compilation
  @skip_oauth_tests not System.get_env("OAUTH_TOKEN")
  
  if @skip_oauth_tests do
    @tag :skip
  end
  test "test requiring oauth token - option 1" do
    assert System.get_env("OAUTH_TOKEN") != nil
  end

  # Option 2: Use ExUnit.configure to exclude tags
  # In test_helper.exs or setup_all:
  # if not System.get_env("OAUTH_TOKEN") do
  #   ExUnit.configure(exclude: [:requires_oauth])
  # end
  
  @tag :requires_oauth
  test "test requiring oauth token - option 2" do
    assert System.get_env("OAUTH_TOKEN") != nil
  end

  # Option 3: Check condition in the test itself
  test "test requiring oauth token - option 3" do
    case System.get_env("OAUTH_TOKEN") do
      nil -> 
        # This will show as passed, not skipped
        IO.puts("Skipping: OAuth token not available")
      token ->
        assert is_binary(token)
        # Your actual test logic here
    end
  end

  # Option 4: Use a custom skip helper that raises
  defp skip_unless(condition, message) do
    unless condition do
      raise ExUnit.AssertionError,
        message: "Test skipped: #{message}",
        expr: {:skip, message}
    end
  end

  test "test requiring oauth token - option 4" do
    skip_unless(System.get_env("OAUTH_TOKEN"), "OAuth token not available")
    
    # Your test logic here
    assert true
  end

  # Option 5: Use setup_all to set module attributes dynamically
  setup_all do
    cond do
      not System.get_env("API_KEY") ->
        IO.puts("\nSkipping all tests in #{__MODULE__}: API key not available")
        # Return context that tests can check
        {:ok, skip_all: true, skip_reason: "API key not available"}
      true ->
        {:ok, skip_all: false}
    end
  end

  setup context do
    if context[:skip_all] do
      # We can't skip from here, but we can set up the context
      # so individual tests can check and handle it
      {:ok, should_skip: true, skip_reason: context[:skip_reason]}
    else
      :ok
    end
  end

  test "test with conditional skip check", context do
    if context[:should_skip] do
      # This is not ideal as it shows as passed, not skipped
      IO.puts("Test skipped: #{context[:skip_reason]}")
    else
      # Your actual test
      assert 1 + 1 == 2
    end
  end
end

# The best practice for your use case is to use ExUnit.configure
# in your test_helper.exs or at the module level:

defmodule BestPracticeExample do
  use ExUnit.Case
  
  # At module level, check once and tag all tests
  if not System.get_env("OAUTH_TOKEN") do
    @moduletag :skip
  end
  
  test "all tests in this module will be skipped if no OAuth token" do
    assert true
  end
end

# Or for individual tests with more granular control:
defmodule GranularSkipExample do
  use ExUnit.Case
  
  # Define a macro for cleaner syntax
  defmacro test_with_oauth(name, body) do
    quote do
      if System.get_env("OAUTH_TOKEN") do
        test unquote(name), unquote(body)
      else
        @tag :skip
        test unquote(name) do
          flunk("OAuth token required")
        end
      end
    end
  end
  
  test_with_oauth "oauth dependent test" do
    token = System.get_env("OAUTH_TOKEN")
    assert is_binary(token)
  end
end