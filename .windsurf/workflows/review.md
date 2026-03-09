---
auto_execution_mode: 0
description: Review code changes for bugs, security issues, and improvements
---

You are a senior Elixir engineer performing a thorough code review on the `elixir_cache` library — an open-source Elixir caching library with pluggable adapters (Agent, ETS, DETS, Redis, ConCache), sandbox testing support, and telemetry.

Before reviewing, read the relevant skill(s) from `.windsurf/skills/` using the `skill` tool. Always start with `modify-elixir-code`. Then read additional skills based on the domains touched by the changes (see `.windsurf/rules/general.md` for the routing table).

## Steps

1. Run `git diff --name-only HEAD~1` (or the relevant commit range) to identify changed files.
2. Read the changed files and surrounding context. Call multiple read tools in parallel.
3. Load the matching skill(s) based on the domains touched.
4. Review the changes against the criteria below and report findings.

## Review criteria

### Correctness
- Logic errors, incorrect pattern matches, missing clauses
- Unhandled edge cases (nil values, empty lists, error tuples)
- Use of `is_nil/1` instead of `== nil` / `!= nil`
- Use of `===` / `!==` instead of `==` / `!=`
- Use of `refute` instead of `assert !` in tests
- Use of `Enum.empty?/1` instead of `length(list) === []`
- Pipes must start with a raw value, not a function call wrapping another (e.g. `a |> b |> c` not `b(a) |> c`)
- No 1-2 letter acronym variable names
- Predicate functions use `?` suffix, not `is_` prefix (except guards)
- No mixing of atom and string keys on the same map without justification

### Concurrency
- Race conditions in GenServer state or ETS access
- Blocking calls in `init/1` — should use `handle_continue` instead
- Proper ETS table ownership and cleanup in adapters

### Security
- No hardcoded secrets or API keys
- No `Application.put_env` in tests
- No `Mix.env()` usage at runtime (only compile-time)

### Caching / Adapter correctness
- Adapter implements all `@behaviour Cache` callbacks correctly
- `opts_definition/0` returns a valid NimbleOptions schema
- Term encoding/decoding round-trips correctly
- Sandbox key prefixing works correctly for test isolation
- Telemetry events emitted with correct names and metadata
- Error handling returns `ErrorMessage` structs consistently

### Testing
- `async: true` where possible, no `async: false` without reason
- Descriptive test names (lowercase, no camelCase)
- Cache.SandboxRegistry used for test isolation
- No mocking libraries

### Style & conventions
- Max line length 120 characters
- No unnecessary comments
- No `use import` of disallowed modules (see `.credo.exs` `ImproperImport`)
- Single pipe check (`Readability.SinglePipe`)
- Pipe chain starts with a value (`Refactor.PipeChainStart`)

## Output format

For each finding, report:
- **File** and **line range**
- **Severity**: 🔴 Bug, 🟡 Warning, 🔵 Suggestion
- **Category**: one of the review criteria sections above
- **Description**: concise explanation of the issue with a suggested fix

If no issues are found, confirm the changes look good.

## Guidelines
- Call multiple tools in parallel when exploring the codebase.
- Report pre-existing bugs found in surrounding code — maintaining code quality matters.
- Do NOT report speculative or low-confidence issues. Base conclusions on actual code understanding.
- If given a specific git commit, it may not be checked out — local code state may differ.
- When reporting issues, reference the specific rule or convention being violated.
