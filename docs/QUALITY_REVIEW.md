# Initial quality review — 2026-09-06

This is a light first pass, not an exhaustive audit or a claim that Jake is bug-free.
Runtime fixes below remain follow-up work. Web UI findings came from a separate
read-only review agent. Findings marked static have not been reproduced dynamically.

## What Jake does

Jake parses a Jakefile into a borrowed-source AST, resolves imports and recipe
references, then executes shell commands with dependencies, hooks, caching and
optional parallelism/watch mode. The formatter renders that AST back to source.
The web UI exposes execution through a local HTTP/WebSocket server and renders
executor lifecycle/output events in a browser.

The most useful bug classes are ownership across source/AST boundaries, cleanup
on parse errors and allocation failures, lexer progress/location bounds, formatter
semantic preservation, repeated-run state reset, dependency scheduling, and event
ordering across execution, cancellation, reconnect and concurrent clients.

## Triage

| Priority | Area and evidence | Finding and confidence | Next action |
| --- | --- | --- | --- |
| High | `src/jake.zig:64-71`, `src/frontend/parser.zig:164,723` | Static: public `load()` frees source before returning an AST whose source and string fields borrow it. The CLI's separate `LoadedJakefile` owns its source; scope is the public library helper. | Give loaded ASTs explicit source ownership and verify their complete lifetime. |
| High | `src/webui/server.zig:742-805,460-476,135-149` | Static concurrency defect: failed broadcasts destroy clients while reader threads retain them and also perform cleanup; shutdown has the same ownership concern. | Establish one cleanup owner and join readers before server teardown. |
| High | `src/webui/server.zig:446,472,482-510,742-861` | Static concurrency defect: direct replies and broadcasts can write concurrently to the same stream. | Serialize every write per connection. |
| High | `src/webui/server.zig:345-357,1137-1159` | Static: HTTP/WebSocket decoding assumes complete transport reads for protocol fields. Ordinary short reads are not consistently handled. | Accumulate bounded HTTP headers and read complete frame fields before decoding. |
| High | `src/webui/server.zig:494-499` | Static: joining the previous execution before checking its running flag waits and launches a second request instead of promptly rejecting it. | Make execution admission and thread ownership one synchronized transition. |
| Medium | `src/runtime/executor.zig:801-823,879-884`, `src/webui/server.zig:670-699` | Static: executor failure paths emit terminal events, then server fallbacks can emit duplicate completion/summary events. | Assign terminal-event ownership; assert exactly one terminal event per task/run. |
| Medium | `src/webui/app.js:66-82,99-160` | Static: reconnect clears active state without an authoritative snapshot; one running-task identifier cannot represent parallel tasks. | Separate run state from an active-task set and restore state at reconnect. |
| Medium | `src/frontend/parser.zig:665-735` | Static: successful parses do not release unconsumed pending metadata lists. The trailing require transfer also lacks cleanup if directive append fails at line 707. | Cover metadata ownership at EOF and allocation-failure cleanup. |
| Medium (addressed) | `src/output/formatter.zig`, fuzz round-trip test | Confirmed test gap: second-pass failure was swallowed and no equality/idempotence assertion ran. | Assertions now fail on second-pass errors or unstable output. |
| Low | `src/webui/app.js:325-328` | Static: dependency controls have button semantics but only click handling. | Use native buttons or add keyboard activation coverage. |

Concurrency findings identify unsafe ownership/synchronization in code; their
frequency and observed runtime effects remain unmeasured. No exploit testing was
performed. Overall review verdict: **Request changes** for the high-priority
runtime findings; the test improvements are a starting point for that work.

## Initial test expansion

- Lexer fuzzing asserts monotonic in-bounds spans and forward progress, with a
  token budget derived from source length. Added deterministic syntax seeds.
- Formatter fuzzing asserts successful second formatting, identical output and
  `changed == false`. Added valid seeds for variables, dependencies and imports.
- A deterministic lifecycle stress test builds 256 recipes and repeats formatting,
  parsing, content checks and teardown eight times using the testing allocator.
  It checks every recipe name and command, rather than only output idempotence.
- Existing coverage-guided targets remain available through `jake fuzz`.

## Next testing passes

1. Add allocation-failure sweeps after fixing parser/source ownership, covering
   successful AST construction, invalid syntax, metadata transfer and imports.
2. Expand structured generation to parameters, hooks, comments, directives,
   imports and dependency graphs; compare AST meaning before and after formatting.
3. Add bounded repeated watch/execute/cancel tests checking state reset, child
   cleanup, descriptor counts and retained memory. Use benign fixture commands.
4. Add web UI state tests for parallel tasks, reconnect and unique terminal events;
   separately test transport read accumulation and connection shutdown ownership.
5. Run longer coverage-guided campaigns and cross-platform CI after fixes; retain
   minimized ordinary regression fixtures for each corrected behavior.

## Validation

Zig 0.15.2 is the CI toolchain. Default local Zig 0.16 failed to compile this
repository; this is already documented in `scripts/zig` and is not a new finding.
Baseline: 1,142 module tests passed, one skipped, plus one executable test.
Expanded suite: 1,143 module tests passed, one skipped, plus one executable test;
11 fuzz targets discovered. Debug build, source formatting and diff checks passed.
These tests cover deterministic fuzz seeds and the bounded lifecycle stress case;
they do not establish the absence of leaks across all paths or validate browser UX.

A coverage-guided smoke command (`zig build fuzz --fuzz -j2`) was stopped at a
60-second wall-clock budget, including compilation/startup. Its log confirmed
the fuzz web interface started and reported no failure, but supplied no execution
counts; no coverage or campaign-completion claim is made.

## Tracked follow-ups

- [#33: Source lifetime and parser cleanup](https://github.com/HelgeSverre/jake/issues/33)
- [#34: Web connection ownership and writes](https://github.com/HelgeSverre/jake/issues/34)
- [#35: Web transport and execution/display state](https://github.com/HelgeSverre/jake/issues/35)
- [#36: Further fuzzing and stress coverage](https://github.com/HelgeSverre/jake/issues/36)
