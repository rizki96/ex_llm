# Credo configuration for ExLLM
# This allows us to gradually improve code quality

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/",
          "config/",
          "mix.exs"
        ],
        excluded: [
          # Exclude files with known issues during transition
          ~r"/_build/",
          ~r"/deps/",
          ~r"/node_modules/"
        ]
      },
      plugins: [],
      requires: [],
      strict: false, # Start with false, gradually enable
      parse_timeout: 15000,
      color: true,
      checks: [
        # Enable warnings (these should always be fixed)
        {Credo.Check.Warning.LazyLogging, []},
        {Credo.Check.Warning.MapGetUnsafePass, []},
        {Credo.Check.Warning.UnsafeToAtom, []},
        {Credo.Check.Warning.UnusedKeywordOperation, []},
        {Credo.Check.Warning.UnusedListOperation, []},
        {Credo.Check.Warning.UnusedPathOperation, []},
        {Credo.Check.Warning.UnusedRegexOperation, []},
        {Credo.Check.Warning.UnusedStringOperation, []},
        {Credo.Check.Warning.UnusedTupleOperation, []},
        {Credo.Check.Warning.RaiseInsideRescue, []},

        # Gradually enable design checks
        {Credo.Check.Design.AliasUsage, [priority: :low]},
        
        # Disable complex function checks for now, re-enable later
        {Credo.Check.Design.DuplicatedCode, false},
        {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 12]}, # Relaxed from 9
        {Credo.Check.Refactor.Nesting, [max_nesting: 3]}, # Relaxed from 2
        
        # Allow TODO comments for now (we have legitimate ones)
        {Credo.Check.Design.TagTODO, [priority: :low]},
        
        # Disable apply/3 warnings for local model loading (necessary for optional deps)
        {Credo.Check.Warning.ApplicationConfigInModuleAttribute, false},
        {Credo.Check.Refactor.Apply, [
          excluded_functions: [
            "Bumblebee.load_model",
            "Bumblebee.load_tokenizer", 
            "Bumblebee.load_generation_config",
            "Nx.Serving.new"
          ]
        ]},

        # Readability checks - enable gradually
        {Credo.Check.Readability.AliasOrder, []},
        {Credo.Check.Readability.LargeNumbers, []},
        {Credo.Check.Readability.MaxLineLength, [max_length: 120]}, # Relaxed from 98
        {Credo.Check.Readability.ModuleAttributeNames, []},
        {Credo.Check.Readability.ModuleDoc, [ignore_names: ["Test", "Mock"]]},
        {Credo.Check.Readability.ModuleNames, []},
        {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
        {Credo.Check.Readability.ParenthesesInCondition, []},
        {Credo.Check.Readability.PredicateFunctionNames, []},
        {Credo.Check.Readability.PreferImplicitTry, []},
        {Credo.Check.Readability.RedundantBlankLines, []},
        {Credo.Check.Readability.Semicolons, []},
        {Credo.Check.Readability.SpaceAfterCommas, []},
        {Credo.Check.Readability.StringSigils, []},
        {Credo.Check.Readability.TrailingBlankLine, []},
        {Credo.Check.Readability.TrailingWhiteSpace, []},
        {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
        {Credo.Check.Readability.VariableNames, []},

        # Consistency checks
        {Credo.Check.Consistency.ExceptionNames, []},
        {Credo.Check.Consistency.LineEndings, []},
        {Credo.Check.Consistency.ParameterPatternMatching, []},
        {Credo.Check.Consistency.SpaceAroundOperators, []},
        {Credo.Check.Consistency.SpaceInParentheses, []},
        {Credo.Check.Consistency.TabsOrSpaces, []},

        # Disable some checks that are too noisy for the current codebase
        {Credo.Check.Readability.AliasAs, false}, # Too many violations
        {Credo.Check.Refactor.LongQuoteBlocks, false}, # Documentation blocks
        {Credo.Check.Design.SkipTestWithoutComment, false}, # Test-specific
      ]
    }
  ]
}