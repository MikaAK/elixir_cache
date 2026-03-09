---
name: modify-elixir-code
description: "Elixir code patterns and conventions for the elixir_cache project. TRIGGER when: writing or modifying ANY Elixir code in this project, including modules, functions, GenServers, supervisors, or any .ex/.exs file. This skill should ALWAYS be read first before any other skill when working with Elixir code. DO NOT TRIGGER when: only modifying non-Elixir files like CI config or documentation."
supporting_files:
  - "references/elixir-style-guide.md"
---

# Elixir Code Guidelines

This skill covers the Elixir language fundamentals, code style, and project-specific patterns required for all Elixir code in the `elixir_cache` library.

For the full community style guide, read `references/elixir-style-guide.md`. The rules below are the most important ones plus project-specific overrides.

## Language Fundamentals

- Lists **do not support index-based access via the access syntax** — use `Enum.at/2`, pattern matching, or `List` functions
- Variables are immutable but can be rebound — block expressions (`if`, `case`, `cond`) must bind their result to a variable:

      # INVALID
      if some_condition do
        value = compute()
      end

      # VALID
      value =
        if some_condition do
          compute()
        end

- **Never** nest multiple modules in the same file (causes cyclic dependencies and compilation errors)
- **Never** use map access syntax (`map[:field]`) on structs — use `my_struct.field`
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in `?` — `is_thing` is reserved for guards only
- OTP primitives like `DynamicSupervisor` and `Registry` require names in child specs: `{DynamicSupervisor, name: MyApp.MyDynamicSup}`
- Use `handle_continue` in GenServers instead of blocking functions in `init`
- `Mix.env()` does not exist at runtime in production releases — use compile-time branching (define two function clauses) instead

## Code Style

- Use `===` over `==` and `!==` over `!=`
- Use `is_nil/1` instead of `== nil` or `!= nil`
- Use `Enum.empty?/1` instead of `length(list) === []`
- Use `refute` instead of `assert !condition` in tests
- Don't use 1 or 2 letter variable names that are acronyms
- Start pipes with a raw value: `a |> b() |> c()` not `b(a) |> c()`
- Avoid using the pipe operator just once — use `String.downcase(str)` not `str |> String.downcase()`
- Never use atoms and strings interchangeably — fix the root cause instead of patching with `Map.get(item, "key")` vs `Map.get(item, :key)`
- Don't add comments unless they are necessary
- Use parentheses for zero-arity function calls so they aren't confused with variables
- Use parentheses when a `def` has arguments, omit them when it doesn't
- Never use `unless` with `else` — rewrite with the positive case first
- Use `true` as the last condition of `cond` (not `:else`)
- Use `do:` for single line `if`/`unless` statements
- Use lowercase error messages when raising exceptions, with no trailing punctuation
- Match strings using the string concatenator: `"my" <> _rest = "my string"`
- Use shorthand map syntax when all keys are atoms: `%{a: 1}` not `%{:a => 1}`
- Use keyword list syntax: `[a: "baz"]` not `[{:a, "baz"}]`
- Omit square brackets from keyword lists when they are optional

## Module Ordering

List module attributes, directives, and macros in this order (blank line between each group, sorted alphabetically within groups):

1. `@moduledoc`
2. `@behaviour`
3. `use`
4. `import`
5. `require`
6. `alias`
7. `@module_attribute`
8. `defstruct`
9. `@type`
10. `@callback` / `@macrocallback` / `@optional_callbacks`
11. `defmacro`, `defguard`, `def`, etc.

## Typespecs and Documentation

- Place `@spec` right before the function definition, after `@doc`, without a blank line separating them
- Name the main type for a module `t`
- Place `@typedoc` and `@type` definitions together, separated by blank lines
- If a union type is too long for one line, put each part on a separate line with leading `|`
- Use `__MODULE__` when a module refers to itself in structs and types
- Use `@moduledoc false` for modules not intended to be documented

## Structs

- Use a list of atoms for fields that default to nil, followed by keyword defaults: `defstruct [:name, :params, active: true]`
- Omit square brackets when defstruct argument is a keyword list only: `defstruct params: [], active: true`

## Project-Specific Patterns

- Use `ErrorMessage` from the `error_message` hex package for structured error returns — no need to alias as `MyApp.ErrorMessage`
- Use `NimbleOptions` for validating keyword option schemas in adapter `opts_definition/0`
- All adapters must implement `@behaviour Cache`
- Warnings in the console are equivalent to errors — fix them
- Don't apply bug fixes that are patches — always fix the root cause
- Don't change behavior of existing code unless asked

## Mix Guidelines

- Read docs before using tasks: `mix help task_name`
- Debug test failures with `mix test test/my_test.exs` or `mix test --failed`
- `mix deps.clean --all` is **almost never needed** — avoid unless you have good reason
- Run `mix credo --strict` and `mix dialyzer` to check for issues
