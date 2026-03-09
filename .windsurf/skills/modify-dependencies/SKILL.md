---
name: modify-dependencies
description: "Dependency management patterns for the elixir_cache project. TRIGGER when: adding dependencies, modifying mix.exs, or changing project configuration. DO NOT TRIGGER when: working with code that doesn't involve dependency or project configuration."
---

# Dependency Management

`elixir_cache` is a single Mix project (not an umbrella). All dependencies are declared directly in `mix.exs`.

## Current Dependencies

**Runtime:**
- `error_message` — structured error returns
- `redix` + `poolboy` — Redis adapter backend
- `con_cache` — ConCache adapter backend
- `nimble_options` — option validation for adapter schemas
- `sandbox_registry` — process registry for test sandbox isolation
- `jason` — JSON encoding/decoding
- `telemetry` + `telemetry_metrics` — telemetry events

**Optional:**
- `prometheus_telemetry` — Prometheus metrics integration

**Dev/Test only:**
- `credo` + `blitz_credo_checks` — linting
- `excoveralls` — test coverage
- `faker` — test data generation
- `dialyxir` — static analysis
- `ex_doc` — documentation generation

## Adding a Dependency

1. Add the dependency to `defp deps` in `mix.exs`
2. Run `mix deps.get`
3. If the dependency is only needed for a specific adapter, consider making it `optional: true`
4. Keep runtime deps minimal — this is a library published on Hex

## Key Rules

- This is a published Hex package — be conservative with runtime dependencies
- Use `optional: true` for adapter-specific backends that consumers may not need
- Dev/test deps should use `only: [:test, :dev]` and `runtime: false` where applicable
- Keep `mix.exs` aliases: `compile` and `test` both use `--warnings-as-errors`
