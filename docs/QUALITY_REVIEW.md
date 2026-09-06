# Quality review and fixes — 2026-09-06

All findings from the initial light review have been addressed. This records the
bounded work completed, not a claim that Jake has no remaining bugs. A separate
agent reviewed the Web UI and reviewed the final server/cancellation changes.

## Fixes

| Finding | Resolution | Coverage |
| --- | --- | --- |
| Public `load()` returned an AST borrowing freed source | Loaded ASTs own their source until `Jakefile.deinit`; `parse()` explicitly borrows source | Loaded-source lifetime and allocation-failure sweep |
| Pending parser metadata leaked on success or transfer failure | Cleanup runs on every parser exit; transferred require arguments have error cleanup | Valid/invalid syntax and allocation-failure sweep |
| Imported paths and failed merges had ownership gaps | Persist origin paths, roll back retirement tracking on merge failure, clean keys/dependency arrays, preserve OutOfMemory | Prefixed/rooted import lifetime and allocation-failure sweep |
| Formatter fuzzing swallowed second-pass failure | Assert successful second format and identical output; preserve OOM classification | Existing seeds, generated syntax semantic comparisons and allocation-failure sweep |
| Unterminated strings and raw escapes destabilized formatting | Reject unterminated quotes; preserve parsed escape bytes and choose a valid quote delimiter | Quote regressions and 1,736 valid single-byte mutations |
| Function and condition calls sliced reversed delimiters | Validate that the closing parenthesis follows the opening parenthesis | Malformed-expression regressions and fuzz targets |
| Invalid text reached environment map assertions | Reject non-WTF-8 environment keys before OS lookup or owned insertion | Invalid-key regression and allocation-failure sweep |
| Broadcast and reader threads could both destroy clients | Readers exclusively destroy clients; shutdown interrupts I/O without recycling descriptors; teardown waits for readers | Repeated connection teardown under testing allocator |
| Concurrent writes could interleave frames | Per-client write lock, failed-write shutdown, socket send timeout | Two concurrent writers, 64 whole messages |
| Protocol fields assumed complete transport reads | Exact-read helper and bounded HTTP header accumulation without consuming following bytes | Chunked in-memory reader, EOF and header-boundary tests |
| Competing run requests waited and launched later | Separate synchronized admission from cancellation and thread cleanup | Second-tab rejection during active execution |
| Duplicate or missing terminal events | Executor task events retained; server supplies missing failed-root lifecycle; one summary after teardown | Normal failure, immediate stop, blocked parallel root, confirmation and repeated runs |
| Reconnect and parallel display state were incomplete | Authoritative run snapshot and active task set; summary belongs to requested root | Node VM state tests and sequential/parallel WebSocket integration |
| Dependency controls lacked keyboard activation | Native buttons | State/render test and source review |
| Stop could race child PID registration or miss parallel children | Each child monitors cancellation; worker lifetime includes monitor join | Immediate stop and cancellation of two simultaneous commands |
| Repeated watch/test execution exposed stale state | Repeated watch reload assertions, pattern allocation cleanup, isolated E2E output fixture | 16 reloads and repeatable full E2E suite |

## Coverage added

The testing allocator checks leaks on exercised unit-test paths. Allocation-failure
sweeps traverse successful and failed construction paths. The structured formatter
fuzz target generates bounded valid recipes with variables, imports, dependencies,
parameters, aliases and metadata, and compares execution-relevant AST fields.
The earlier 256-recipe/eight-iteration lifecycle test remains in place.

Web tests cover admission locking, repeated runs, dependency output, non-zero exit,
confirmation, immediate cancellation, reconnect snapshots, parallel task state,
root summary routing, bounded browser output and disconnect control refresh.

## Validation

Use Zig 0.15.2, as in CI (`scripts/zig` resolves a compatible compiler).
Validation completed with 1,160 module tests passing, one platform-specific test
skipped, and the library import test passing. The deterministic formatter mutation
campaign checked 1,736 valid mutations. WebSocket integration covers repeated
execution, confirmation, reconnect, competing clients and cancellation of parallel
child processes.

Twelve coverage-guided fuzz targets were compiled separately with LLVM
instrumentation. Ten completed their bounded campaigns, the parser campaign
completed without a Jake failure, and the raw formatter campaign eventually
stopped in Zig's own `lib/fuzzer.zig` memory-mapped corpus code. The formatter's
deterministic seeds, semantic generator and mutation campaign all passed.

Cross-platform compilation does not substitute for running those platform tests.
Node VM tests exercise browser state and DOM updates; they do not replace visual
browser testing. Reconnection restores active state, not missed output history.
The bounded fuzz campaign is not exhaustive. Zig 0.15.2's multi-target fuzzer
coordinator can crash when it selects the self-hosted backend, so the fuzz build
explicitly uses LLVM and targets were run separately. No exploit testing was
performed.

## Tracking

- [#33: Source lifetime and parser cleanup](https://github.com/HelgeSverre/jake/issues/33)
- [#34: Web connection ownership and writes](https://github.com/HelgeSverre/jake/issues/34)
- [#35: Web transport and execution/display state](https://github.com/HelgeSverre/jake/issues/35)
- [#36: Further fuzzing and stress coverage](https://github.com/HelgeSverre/jake/issues/36)
