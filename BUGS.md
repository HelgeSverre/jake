# Bugs and reliability issues

Recorded 2026-09-12 from a static security review of revision
`43ef72e22b88696239787626fc60e5e91976ccda`.

These are open issues, not completed fixes. The review covered 110 files,
including all 40 Zig files under `src/`; ancillary repository coverage was
partial. No vulnerability triggers or runtime reproductions were executed.
Severity reflects the stated local-access, timing, platform, and allocation
failure prerequisites. Reliability observations below are separate from the
11 reported security findings (3 medium, 8 low).

## Security findings

### 1. Upgrade response cleanup can double-free memory — Low

- **Where:** `src/cli/upgrade.zig:185-198` (`httpGet`).
- **Bug:** The response body has an `errdefer` free, but the nonzero child-exit
  branch explicitly frees it before returning an error, freeing it again.
- **Impact:** A failed transfer with an allocated response can cause an
  allocator failure or memory corruption instead of a clean update error.
- **Fix:** Keep one owner for error cleanup. Also switch on the child termination
  union before reading `Exited`, and reap children on post-spawn errors.

### 2. Loader error cleanup can double-free a watch-path key — Low

- **Where:** `src/frontend/jakefile_loader.zig:185-231`.
- **Bug:** `collectImportWatchFiles` leaves its key-freeing `errdefer` active
  after inserting the key into `seen_realpaths`. A later error frees it locally,
  and the caller's map cleanup frees it again.
- **Impact:** Later I/O, parsing, or allocation errors during watch-file
  collection can corrupt allocator state. Initial parsing may reject ordinary
  malformed input before this second pass.
- **Fix:** Transfer key ownership exactly once; end the local cleanup guard
  after insertion, or remove the entry before freeing it.

### 3. Parallel worker registration failure can cause use-after-free — Low

- **Where:** `src/runtime/parallel.zig:348-363`;
  `src/runtime/executor.zig:842-857`.
- **Bug:** A worker starts before its handle is appended to a fallible list.
  If that append fails, the live worker is omitted from the join loop.
- **Impact:** Under allocation failure, executor teardown can release state
  while the unjoined worker still accesses it or continues commands.
- **Fix:** Reserve handle-list capacity before spawning, then append without
  allocation. Join every successfully spawned worker on every exit path.

### 4. Web UI control connections are unauthenticated — Medium

- **Where:** `src/webui/server.zig:183-189`, `420-424`, `502-559`, `646-700`.
- **Bug:** WebSocket clients need no per-session credential to request recipe
  execution, stop runs, or approve pending confirmations.
- **Impact:** A separate local account that can reach the loopback listener can
  act with the server owner's recipe-execution authority. The service is
  optional and loopback-only; remote network exposure is not assumed.
- **Fix:** Require a high-entropy per-launch capability before accepting control
  connections, protect its handoff, and bind confirmations to authenticated
  clients. Validate browser Origin as an additional control.

### 5. Upgrade downloads use an unsafe shared temporary pathname — Medium

- **Where:** `src/cli/upgrade.zig:211-228`, `477-519`.
- **Bug:** The timestamp-based `/tmp` download path is not exclusively created
  in private storage. Download, verification, and installation reopen paths.
- **Impact:** A local attacker sharing temporary storage may redirect the
  download into another victim-writable file. This requires pathname control
  and timing; OS symlink and sticky-directory protections constrain variants.
  Verification after writing does not prevent earlier truncation damage.
- **Fix:** Use exclusive creation in an owner-only temporary directory and
  preserve the verified file's identity through installation.

### 6. Dry-run cache persistence can write outside the project — Medium

- **Where:** `src/runtime/cache.zig:219-226`;
  `src/runtime/context.zig:166-174`; `src/main.zig:293-330`, `367-368`.
- **Bug:** Dry-run leaves cache saving enabled. Cache creation follows the
  `.jake/cache` path without rejecting linked components.
- **Impact:** A checkout-controlled link can redirect cache truncation to a
  victim-writable file even when recipe commands are not executed. Initial
  cache loading and OS permissions must also permit the path. Listing and
  `--show` already suppress persistence.
- **Fix:** Disable persistence during dry-run. For normal saves, use a verified
  directory handle and safe atomic replacement without following cache links.

### 7. In-place formatting reopens a replaceable pathname — Low

- **Where:** `src/output/formatter.zig:59-73`; `src/main.zig:181-190`.
- **Bug:** The formatter reads a file and later reopens its pathname for writing.
  The CLI redundantly writes it a second time.
- **Impact:** A concurrent writer to a shared input directory can redirect a
  write to another victim-writable file. A private checkout removes that actor.
- **Fix:** Give one component responsibility for writing and bind replacement
  to a verified parent directory/file identity.

### 8. Timeout arithmetic is unchecked — Low

- **Where:** `src/frontend/parser.zig:678-694`;
  `src/runtime/executor.zig:1294-1297`.
- **Bug:** Minute/hour conversion can overflow `u64`; subsequent conversion
  to milliseconds and an `i64` deadline is also unchecked.
- **Impact:** Caller-supplied parser input can terminate a safety-enabled host.
  Unchecked builds have invalid arithmetic behavior and may compute incorrect
  deadlines. No remote parser deployment is assumed.
- **Fix:** Check unit multiplication, integer conversion, and deadline addition;
  return an error before execution for unsupported durations.

### 9. Editor scanner passes Unicode to narrow `isspace` — Low

- **Where:** `editors/tree-sitter-jake/src/scanner.c:193-208`;
  `editors/tree-sitter-jake/src/tree_sitter/parser.h:43`.
- **Bug:** `TSLexer.lookahead` is a full code point, but narrow `isspace`
  requires EOF or a value representable as `unsigned char`.
- **Impact:** Opening a document in an affected native editor integration can
  invoke undefined behavior, potentially an out-of-bounds read or crash.
  Manifestation depends on the C library and scanner state; no write primitive
  was established.
- **Fix:** Use explicit ASCII whitespace comparisons matching the grammar.

### 10. WebSocket clients retain unbounded resources — Low

- **Where:** `src/webui/server.zig:420-477`.
- **Bug:** Each accepted client gets a detached reader thread; the receive
  timeout is removed and no aggregate client limit is enforced.
- **Impact:** Local clients can exhaust threads, descriptors, or memory.
  Individual frame limits do not bound total client resources.
- **Fix:** Cap clients and aggregate payload memory, enforce read/idle deadlines,
  and use bounded connection processing.

### 11. Completion installation bypasses zsh directory checks — Low

- **Where:** `src/cli/completions.zig:171-180`, `227-233`.
- **Bug:** The persistent `.zshrc` block invokes `compinit -u`, bypassing
  ownership/permission checks across the completion search path.
- **Impact:** An already-insecure completion directory can supply definitions
  that the normal guard would reject. The normal private home-directory install
  is not itself writable by other users.
- **Fix:** Remove `-u`; report insecure paths and guide permission repair.

## Signal and child-process reliability

These source-backed defects or limitations were not elevated to security
findings without a stronger attacker boundary. They still deserve fixes.

| Issue | Source | Recommended change |
| --- | --- | --- |
| Ordinary commands and hooks do not get dedicated process groups. A signal sent directly to Jake may reach only the shell wrapper, leaving descendants alive. | `src/runtime/executor.zig:1688-1694`; `src/runtime/hooks.zig:208-231`; `src/runtime/signals.zig:95-99` | Define a consistent child-group policy while preserving interactive terminal behavior. |
| The fixed signal registry silently omits children above 256 concurrent entries. | `src/runtime/signals.zig:28-70` | Reserve tracking capacity before spawning, enforce a matching limit, or redesign supervision. |
| A signal between spawn and registration can make Jake exit before forwarding to the new child. | `src/runtime/executor.zig:1704-1714`; `src/runtime/signals.zig:123-138` | Coordinate shutdown in normal control flow and stop spawning before forwarding/reaping. |
| Raw numeric PIDs can be reaped/reused before a handler, timeout watchdog, or cancellation monitor acts on a previously loaded value. | `src/runtime/signals.zig:114-120`; `src/runtime/executor.zig:1276-1286`, `1937-1983` | Synchronize signaling with reaping; use stable process handles where available. Atomics alone do not preserve OS process identity. |
| Failed output-drain thread creation can leave a pipe unread while the parent waits, hanging the command. | `src/runtime/executor.zig:1913-1927` | Treat drain setup failure as fatal and clean up the child, or provide a safe draining fallback. |
| If the first parallel worker cannot start, execution can return success without running tasks. | `src/runtime/parallel.zig:352-375` | Return a resource error or execute sequentially when no worker starts. |
| Just metadata discovery and upgrade HTTP helpers can return on output-read errors without terminating/reaping their child. | `src/frontend/external.zig:269-282`; `src/cli/upgrade.zig:185-191` | Install post-spawn cleanup covering every error path, with exactly one reap. |
| Upgrade, browser-launch, and Just metadata helper processes bypass the runtime signal registry. | `src/cli/upgrade.zig:167-231`; `src/webui/server.zig:1309-1321`; `src/frontend/external.zig:253-284` | Make helper supervision policy explicit and apply shared cleanup where appropriate. |

Terminal Ctrl-C can mask missing descendant forwarding because the terminal
signals its foreground group independently. Direct SIGTERM/SIGHUP delivery is
different. Children that deliberately ignore forwarded signals may survive:
`src/runtime/signals.zig:10-21` documents that Jake does not escalate these
signals to SIGKILL.

## Other robustness follow-up

- **Shared default context race:** Parallel worker constructors reset the same
  non-atomic `default_context` (`src/runtime/executor.zig:165-169`;
  `src/runtime/parallel.zig:551-567`). Give each executor its own context.
- **OOM cleanup leaks:** External recipe merging omits some transferred and
  untransferred allocations on error (`src/frontend/external.zig:647-703`).
  Watch insertion paths also lose allocations on failed ownership transfer
  (`src/runtime/watch.zig:297-419`). Centralize transactional cleanup.
- **Import budgets:** Cycle detection and per-file size limits do not constrain
  acyclic recursion depth or total graph resources
  (`src/frontend/import.zig:249-281`, `344`). Add explicit cumulative limits.
- **Global import diagnostics:** Failure-path storage is unsynchronized global
  state (`src/frontend/import.zig:34-46`). Use per-resolver diagnostics for
  concurrent library callers.
- **Cache digest validation — unresolved:** `Cache.load` ignores the decoded
  byte count (`src/runtime/cache.zig:200-206`). Confirm the compiler-library
  contract and require a complete 32-byte digest before accepting a record.

## Validation when fixing

Add focused regression coverage for the repaired invariant: allocation-failure
unwinding, complete thread joining, post-spawn cleanup, checked duration
conversion, authenticated control access, and safe file replacement. Exercise
process-group and signal behavior on supported platforms. Do not treat this
static review as runtime verification of the fixes.
