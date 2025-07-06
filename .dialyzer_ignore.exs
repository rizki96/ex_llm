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
  # Note: Logger macro warnings resolved in current Elixir version
  
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
  {"lib/mix/tasks/ex_llm.validate.ex", :callback_info_missing},
  
  # === OPTIONAL DEPENDENCIES (Legitimate) ===
  # Ecto is an optional dependency properly handled with Code.ensure_loaded?
  ~r/Function Ecto\.Changeset\./,
  
  # === FALSE POSITIVES FROM DIALYZER LIMITATIONS ===
  # These are documented false positives due to Dialyzer's inability to trace through:
  # - Dynamic test interceptor conditionals
  # - Complex case statement analysis
  # - Macro-generated code
  
  
  # Optional Nx dependency for local models
  ~r/Function Nx\.Serving\.run\/2 does not exist/,
  
  # === PHASE 3.3 REMAINING WARNINGS (False Positives) ===
  
  # Test caching interception - dialyzer can't trace through the control flow
  # REMOVED: handle_tesla_response now uses ExLLM.HTTP wrapper, no longer needed
  # {"lib/ex_llm/plugs/execute_request.ex", :call},
  
  
  
  # Streaming compatibility defensive pattern match - false positive
  # start_stream function returns {:ok, id} but dialyzer can't trace through defensive code
  {"lib/ex_llm/providers/shared/streaming/compatibility.ex", :pattern_match},
  
  # === TESLA ENV TYPE WARNINGS RESOLVED ===
  # These warnings were resolved by using ExLLM.HTTP wrapper module
  # instead of pattern matching directly on Tesla.Env structs.
  
  # === OPENAI-COMPATIBLE MACRO EXPANSIONS (False Positives) ===
  # The OpenAICompatible macro generates code that dialyzer can't properly analyze
  # These warnings occur because dialyzer can't see through the macro expansion
  {"lib/ex_llm/providers/lmstudio.ex", :guard_fail},
  {"lib/ex_llm/providers/lmstudio.ex", :pattern_match},
  {"lib/ex_llm/providers/lmstudio.ex", :pattern_match_cov},
  {"lib/ex_llm/providers/mistral.ex", :call},
  {"lib/ex_llm/providers/mistral.ex", :pattern_match_cov},
  {"lib/ex_llm/providers/openrouter.ex", :guard_fail},
  {"lib/ex_llm/providers/openrouter.ex", :pattern_match},
  {"lib/ex_llm/providers/openrouter.ex", :pattern_match_cov},
  {"lib/ex_llm/providers/perplexity.ex", :guard_fail},
  {"lib/ex_llm/providers/perplexity.ex", :pattern_match},
  {"lib/ex_llm/providers/perplexity.ex", :pattern_match_cov},
]