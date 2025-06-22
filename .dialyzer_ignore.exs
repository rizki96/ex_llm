# Professional Dialyzer Suppressions for ExLLM
# 
# This file contains only legitimate suppressions for:
# 1. Elixir/OTP macro-generated functions (unavoidable)
# 2. Mix compile-time functions (unavoidable)
# 3. Test-only dependencies (test environment only)
#
# All other dependencies (Jason, Req, Tesla, Telemetry) should be properly 
# resolved via PLT configuration, not suppressed.

[
  # === ELIXIR/OTP MACRO EXPANSIONS (Legitimate) ===
  # Logger macros generate these functions at compile time
  # These functions exist but are not visible to static analysis
  ~r/Function Logger\.__do_log__\/4 does not exist/,
  ~r/Function Logger\.__should_log__\/2 does not exist/,
  
  # === MIX COMPILE-TIME FUNCTIONS (Legitimate) ===
  # Mix functions are available at compile time but not in runtime PLT
  ~r/Function Mix\.shell\/0 does not exist/,
  ~r/Function Mix\.env\/0 does not exist/,
  
  # === TEST-ONLY DEPENDENCIES (Legitimate) ===
  # ExUnit is only available in test environment
  ~r/Function ExUnit\./,
  
  # === MIX TASK BEHAVIOR CALLBACKS (Legitimate) ===
  # Mix.Task behavior callbacks not found in PLT
  {"lib/mix/tasks/ex_llm.cache.ex", :callback_info_missing},
  {"lib/mix/tasks/ex_llm.config.ex", :callback_info_missing},
  
  # === OPTIONAL DEPENDENCIES (Legitimate) ===
  # Ecto is an optional dependency properly handled with Code.ensure_loaded?
  ~r/Function Ecto\.Changeset\./
]