allowed_imports = [
  [:Absinthe],
  [:ChannelCase],
  [:DataCase],
  [:EctoEnum],
  [:Ecto],
  [:ExUnit, :CaptureLog],
  [:ExUnit],
  [:Mix],
  [:Plug],
  [:Router, :Helpers],
  [:Telemetry, :Metrics]
]

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/",
          "mix.exs",
          ".credo.exs"
        ],
        excluded: [~r"_build/", ~r"deps/"]
      },
      plugins: [],
      strict: true,
      parse_timeout: 10_000,
      color: true,
      checks: [

        # BlitzCredoChecks

        {BlitzCredoChecks.SetWarningsAsErrorsInTest, false},
        {BlitzCredoChecks.DocsBeforeSpecs, []},
        {BlitzCredoChecks.DoctestIndent, []},
        {BlitzCredoChecks.NoAsyncFalse, []},
        {BlitzCredoChecks.NoDSLParentheses, []},
        {BlitzCredoChecks.NoIsBitstring, []},
        {BlitzCredoChecks.StrictComparison, false},
        {BlitzCredoChecks.UseStream, []},
        {BlitzCredoChecks.LowercaseTestNames, []},
        {BlitzCredoChecks.ImproperImport, allowed_modules: allowed_imports},

        # MikaCredoRules (supersedes BlitzCredoChecks.StrictComparison, TagTODO, TagFIXME)
        {MikaCredoRules.AsyncTrueRequired, []},
        {MikaCredoRules.CredoConfigNamedDefault, []},
        {MikaCredoRules.DistributionRequiresBuckets, []},
        {MikaCredoRules.EnsureLoadedBeforeExported, []},
        # lib/cache/ets.ex: opts_definition/1 is a NimbleOptions :custom validator, whose contract
        # is {:error, String.t()}
        {MikaCredoRules.ErrorMessageRequired, [excluded_paths: ["_test.exs", "test/", "lib/cache/ets.ex"]]},
        {MikaCredoRules.ExceptionNamesEndInError, []},
        {MikaCredoRules.GenServerRequiresHandleContinue, []},
        {MikaCredoRules.LoggerModulePrefixAndInspect, []},
        {MikaCredoRules.LowercaseErrorMessages, []},
        {MikaCredoRules.NoAccessOnStructSubject, []},
        {MikaCredoRules.NoApplicationEnvOutsideConfig, []},
        {MikaCredoRules.NoAtomStringKeyFallback, []},
        {MikaCredoRules.NoBarePatternMatchOnFallible, []},
        {MikaCredoRules.NoBinaryPatternForStringPrefix, []},
        {MikaCredoRules.NoBlanketRescue, []},
        {MikaCredoRules.NoBooleanLiteralComparison, []},
        {MikaCredoRules.NoCondElseAtom, []},
        {MikaCredoRules.NoDoPrefixedHelper, []},
        {MikaCredoRules.NoForWithDiscardedResult, []},
        {MikaCredoRules.NoHardcodedSecretLiterals, []},
        {MikaCredoRules.NoIOANSIRawEscapes, []},
        {MikaCredoRules.NoIdentityRewrap, []},
        {MikaCredoRules.NoIntermediateSingleUseVariable, []},
        {MikaCredoRules.NoKernelPrefix, []},
        {MikaCredoRules.NoLengthZeroComparison, []},
        {MikaCredoRules.NoMixEnvAtRuntime, []},
        {MikaCredoRules.NoMockingLibraries, []},
        {MikaCredoRules.NoNilComparison, []},
        {MikaCredoRules.NoPipeIntoControlFlow, []},
        {MikaCredoRules.NoProcessSleepInTests, []},
        {MikaCredoRules.NoSelfSendZeroDelay, []},
        {MikaCredoRules.NoSingleLetterVariables, []},
        {MikaCredoRules.NoTaskAsyncInGenServer, []},
        {MikaCredoRules.NoTruthyAndOr, []},
        {MikaCredoRules.NoUnboundBlockAssignment, []},
        {MikaCredoRules.NoUnsupervisedTaskStart, []},
        {MikaCredoRules.NoVacuousAssert, []},
        {MikaCredoRules.NoWordSigilLists, []},
        {MikaCredoRules.RefuteOverAssertNot, []},
        {MikaCredoRules.SingleModulePerFile,
         [excluded_paths: ["test/", "test/support/", "_test.exs", "cache_test_modules.ex"]]},
        {MikaCredoRules.StrictEquality, []},
        {MikaCredoRules.TaskAsyncStreamRequiresTimeout, []},
        {MikaCredoRules.TestOnlyDepsScoped,
         [test_only_packages: [:credo, :blitz_credo_checks, :mika_credo_rules, :dialyxir, :excoveralls, :ex_doc]]},
        {MikaCredoRules.TodosNeedTickets, []},

        # MikaCredoRules that target consumers of this library, not the library itself
        {MikaCredoRules.CacheOptsNoHardcodedUri, false},
        {MikaCredoRules.CacheRequiresSandboxOption, false},
        {MikaCredoRules.NoDirectErlangRpc, false},
        {MikaCredoRules.NoRawEts, false},
        {MikaCredoRules.NoReimplementedHelper, false},

        # Consistency Checks
        {Credo.Check.Consistency.ExceptionNames, []},
        {Credo.Check.Consistency.LineEndings, []},
        {Credo.Check.Consistency.ParameterPatternMatching, []},
        {Credo.Check.Consistency.SpaceAroundOperators, []},
        {Credo.Check.Consistency.SpaceInParentheses, []},
        {Credo.Check.Consistency.TabsOrSpaces, []},

        # Design Checks
        {Credo.Check.Design.AliasUsage, false},

        # No outstanding TODOs
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Design.TagFIXME, false},

        # # Readability Checks
        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Readability.FunctionNames, []},
        {Credo.Check.Readability.LargeNumbers, []},
        {Credo.Check.Readability.MaxLineLength, [max_length: 120]},
        {Credo.Check.Readability.ModuleAttributeNames, []},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Readability.ModuleNames, []},
        {Credo.Check.Readability.ParenthesesInCondition, []},
        {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
        {Credo.Check.Readability.PredicateFunctionNames, []},
        {Credo.Check.Readability.PreferImplicitTry, []},
        {Credo.Check.Readability.RedundantBlankLines, false},
        {Credo.Check.Readability.Semicolons, []},
        {Credo.Check.Readability.SpaceAfterCommas, false},
        {Credo.Check.Readability.StringSigils, []},
        {Credo.Check.Readability.TrailingBlankLine, false},
        {Credo.Check.Readability.TrailingWhiteSpace, false},
        {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
        {Credo.Check.Readability.VariableNames, []},
        #
        # Refactoring Opportunities
        {Credo.Check.Refactor.CondStatements, []},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        {Credo.Check.Refactor.FunctionArity, []},
        {Credo.Check.Refactor.LongQuoteBlocks, false},
        {Credo.Check.Refactor.MapInto, false},
        {Credo.Check.Refactor.MatchInCondition, []},
        {Credo.Check.Refactor.NegatedConditionsInUnless, []},
        {Credo.Check.Refactor.NegatedConditionsWithElse, []},
        {Credo.Check.Refactor.Nesting, false},
        {Credo.Check.Refactor.UnlessWithElse, []},
        {Credo.Check.Refactor.WithClauses, []},

        # Warnings
        {Credo.Check.Warning.BoolOperationOnSameValues, []},
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
        {Credo.Check.Warning.IExPry, []},
        {Credo.Check.Warning.IoInspect, []},
        {Credo.Check.Warning.LazyLogging, false},
        {Credo.Check.Warning.MixEnv, false},
        {Credo.Check.Warning.OperationOnSameValues, []},
        {Credo.Check.Warning.OperationWithConstantResult, []},
        {Credo.Check.Warning.RaiseInsideRescue, []},
        {Credo.Check.Warning.UnusedEnumOperation, []},
        {Credo.Check.Warning.UnusedFileOperation, []},
        {Credo.Check.Warning.UnusedKeywordOperation, []},
        {Credo.Check.Warning.UnusedListOperation, []},
        {Credo.Check.Warning.UnusedPathOperation, []},
        {Credo.Check.Warning.UnusedRegexOperation, []},
        {Credo.Check.Warning.UnusedStringOperation, []},
        {Credo.Check.Warning.UnusedTupleOperation, []},
        {Credo.Check.Warning.UnsafeExec, []},

        # Controversial and experimental checks
        {Credo.Check.Readability.StrictModuleLayout, false},
        {Credo.Check.Consistency.MultiAliasImportRequireUse, false},
        {Credo.Check.Consistency.UnusedVariableNames, false},
        {Credo.Check.Design.DuplicatedCode, false},
        {Credo.Check.Readability.AliasAs, false},
        {Credo.Check.Readability.MultiAlias, false},
        {Credo.Check.Readability.Specs, false},
        {Credo.Check.Readability.SinglePipe, []},
        {Credo.Check.Readability.WithCustomTaggedTuple, []},
        {Credo.Check.Refactor.ABCSize, false},
        {Credo.Check.Refactor.AppendSingleItem, false},
        {Credo.Check.Refactor.DoubleBooleanNegation, false},
        {Credo.Check.Refactor.ModuleDependencies, false},
        {Credo.Check.Refactor.NegatedIsNil, false},
        {Credo.Check.Refactor.PipeChainStart, []},
        {Credo.Check.Refactor.VariableRebinding, false},
        {Credo.Check.Warning.LeakyEnvironment, false},
        {Credo.Check.Warning.MapGetUnsafePass, false},
        {Credo.Check.Warning.UnsafeToAtom, false}
      ]
    }
  ]
}
