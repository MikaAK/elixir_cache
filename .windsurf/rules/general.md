---
trigger: always_on
---

## Skill Routing

Before working on code in this project, you **must** read the relevant skill(s) from `.windsurf/skills/`. Each skill is a directory containing a `SKILL.md` file with domain-specific patterns, conventions, and requirements. Some skills also have a `references/` subdirectory with additional documentation to read when needed.

To read a skill, use the `skill` tool with the skill name (e.g., `modify-elixir-code`).

### Required skills by task type

| Task | Required Skill(s) |
|------|-------------------|
| Writing or modifying **any Elixir code** | `modify-elixir-code` (always read first) |
| Cache adapters, sandbox, telemetry, `use Cache` macro | `modify-caching` |
| Tests, test support modules, test configuration | `modify-tests` |
| Adding or modifying dependencies in mix.exs | `modify-dependencies` |

### Skill composition

Many tasks require multiple skills. For example:
- Adding a new adapter → `modify-elixir-code` + `modify-caching` + `modify-tests`
- Adding a new dependency → `modify-elixir-code` + `modify-dependencies`

**Always read `modify-elixir-code` first** when writing any Elixir code.

### Global coding standards

- Warnings are errors — fix them
- Don't apply bug fixes that are patches — always fix the root cause
- Don't change behavior of existing code unless asked
- Don't add comments unless necessary
- Run tests after writing them
- Run `mix credo --strict` and `mix dialyzer` to check for issues

### Project overview

`elixir_cache` is an open-source Elixir library (single Mix project, not an umbrella) that provides a unified caching API with pluggable adapters. Key aspects:
- **Adapters**: `Cache.Agent`, `Cache.ETS`, `Cache.DETS`, `Cache.Redis`, `Cache.ConCache`
- **Sandbox testing**: `Cache.Sandbox` + `Cache.SandboxRegistry` for async-safe test isolation
- **Telemetry**: Built-in telemetry events for all cache operations
- **Term encoding**: Automatic binary term encoding/decoding via `Cache.TermEncoder`
- Published on Hex as `elixir_cache`

### Skill references

Some skills have a `references/` subdirectory with larger reference documents. These are loaded on demand — the SKILL.md will tell you when to read them. Current reference files:
- `modify-elixir-code/references/elixir-style-guide.md` — Full Elixir community style guide
- `modify-caching/references/elixir-cache-reference.md` — elixir_cache library API reference
