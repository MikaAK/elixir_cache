# Implementation Plan: Sandbox Adapter Parity

## Goal
Make `Cache.Sandbox` behave as a drop-in replacement for Redis/ETS/DETS/ConCache adapters so all adapter-specific tests pass when `sandbox?` is enabled.

## Discoveries (Audit)
- Redis JSON operations in sandbox return `:ok` instead of `{:ok, count}` for `json_delete/2`, `json_incr/3`, `json_clear/3`, `json_array_append/4`.
- Redis hash operations in sandbox return `:ok` for `hash_set/3`, `hash_delete/2`, and `hash_set_many/1` when adapter tests expect `{:ok, count}` or `{:ok, [counts]}` with TTL.
- ETS `info/0` in sandbox does not include `:name` which ETS tests require.
- ETS/DETS conversion APIs (`to_dets`, `from_dets`, `to_ets`, `from_ets`) return `{:error, :not_supported_in_sandbox}` but tests expect working conversions.
- ETS/DETS macros bypass sandbox because they call `:ets`/`:dets` directly even when `sandbox?` is enabled.
- ConCache-specific APIs (`get_or_store/3`, `dirty_get_or_store/2`) are missing from sandbox but tests call them.

## Plan
1. Align Redis-style operations in `Cache.Sandbox`.
   - Match return values and error tuples for hash and JSON operations.
   - Ensure scan/hash_scan results match Redis adapter expectations.

2. Make ETS/DETS APIs sandbox-aware.
   - Update `Cache.ETS` and `Cache.DETS` macros to delegate to `Cache.Sandbox` when `sandbox?` is true.
   - Implement missing sandbox equivalents for ETS/DETS conversion and file APIs required by tests.
   - Ensure `info/0` returns the `:name` field for ETS.

3. Implement ConCache API parity.
   - Add `get_or_store/3` and `dirty_get_or_store/2` in `Cache.Sandbox` with matching semantics.

4. Add sandbox parity tests.
   - Mirror adapter-specific tests (Redis hash/JSON, ETS, DETS, ConCache) using sandbox-enabled caches.
   - Keep expectations identical to adapter tests.

## Verification
- Run adapter tests against sandbox-enabled modules.
- Confirm no warnings and that new parity tests pass.
