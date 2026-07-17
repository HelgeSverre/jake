# Line Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make trailing, unescaped backslashes join indented recipe lines into one normalized shell command while preserving multiline source formatting.

**Architecture:** The parser groups continued physical lines into one `Recipe.Command` backed by the original source slice. The executor normalizes that slice immediately before expansion and execution, so formatting retains source breaks while the shell receives one line.

**Tech Stack:** Zig 0.15.2, Jake parser/executor/formatter, embedded Zig tests, Jake E2E fixtures.

## Global Constraints

- A backslash must be immediately before LF or CRLF to continue.
- Odd trailing backslash counts continue; even counts remain literal.
- Remove the continuation backslash, line ending, and next line's spaces or tabs without inserting whitespace.
- Continued lines must remain indented recipe lines.
- Preserve multiline source spelling for `jake --fmt`.
- Keep `@cd`, `@shell`, `@pre`, `@post`, and `@on_error` single-line.
- Use `./scripts/zig` so tests run with Zig 0.15.2 rather than the incompatible system Zig 0.16 compiler.

---

### Task 1: Parse logical command boundaries

**Files:**

- Modify: `src/parser.zig`
- Test: `src/parser.zig`

**Interfaces:**

- Produces: `fn lineEndsWithContinuation(source: []const u8, line_end: usize) bool`
- Produces: one `Recipe.Command` whose `line` slice spans every continued physical line

- [ ] **Step 1: Write failing parser regressions**

Add tests proving two-line, multi-line, silent, even-backslash, trailing-space, CRLF, and top-level-boundary behavior. The primary assertion is:

```zig
try std.testing.expectEqual(@as(usize, 1), recipe.commands.len);
try std.testing.expectEqualStrings(
    "echo one \\\n        two",
    recipe.commands[0].line,
);
```

- [ ] **Step 2: Verify the parser regressions fail for the missing behavior**

Run:

```bash
./scripts/zig test src/parser.zig --test-filter "line continuation"
```

Expected: the two-line case reports two commands rather than one.

- [ ] **Step 3: Add raw-line continuation detection**

Add this focused helper near `parseRecipeBody`:

```zig
fn lineEndsWithContinuation(source: []const u8, line_end: usize) bool {
    var end = line_end;
    if (end > 0 and source[end - 1] == '\r') end -= 1;

    var backslashes: usize = 0;
    while (end > backslashes and source[end - backslashes - 1] == '\\') {
        backslashes += 1;
    }
    return backslashes % 2 == 1;
}
```

Change the normal command scan in `parseRecipeBody` to keep consuming `newline` + `indent` while the current physical line continues. Do not consume a non-indented token after the newline; it remains the next top-level parser token.

- [ ] **Step 4: Verify parser behavior**

Run the filtered parser tests again. Expected: all line-continuation parser tests pass.

- [ ] **Step 5: Commit parser behavior**

```bash
git add src/parser.zig
git commit -m "fix(parser): group continued recipe lines"
```

### Task 2: Normalize logical commands before execution

**Files:**

- Modify: `src/executor.zig`
- Test: `src/executor.zig`

**Interfaces:**

- Consumes: multiline `Recipe.Command.line` slices from Task 1
- Produces: `fn normalizeLineContinuations(allocator: std.mem.Allocator, line: []const u8) ![]const u8`
- Contract: returns `line` unchanged when no continuation exists; otherwise returns an allocated normalized slice

- [ ] **Step 1: Write failing normalization tests**

Cover LF, CRLF, multiple continuations, no inserted separator, odd/even backslashes, trailing spaces, and unchanged-pointer behavior. Include:

```zig
const input =
    \\start=3000; p=$start; \
    \\    p=$((p+1)); \
    \\    echo $p
;
const normalized = try normalizeLineContinuations(std.testing.allocator, input);
defer if (normalized.ptr != input.ptr) std.testing.allocator.free(normalized);
try std.testing.expectEqualStrings(
    "start=3000; p=$start; p=$((p+1)); echo $p",
    normalized,
);
```

- [ ] **Step 2: Verify normalization tests fail**

Run:

```bash
./scripts/zig test src/executor.zig --test-filter "line continuation"
```

Expected: compilation fails because `normalizeLineContinuations` does not exist.

- [ ] **Step 3: Implement minimal normalization**

Scan for LF boundaries, account for an optional preceding CR, count immediately preceding backslashes, remove one backslash for odd counts, and skip spaces/tabs after the newline. Allocate only after finding a real continuation.

- [ ] **Step 4: Normalize before all expansions**

At the beginning of `runCommandWithTimeout`, call `normalizeLineContinuations`. Append an allocated result to `expanded_strings`, then pass it to `expandJakeVariables` instead of passing `cmd.line` directly:

```zig
const normalized = normalizeLineContinuations(self.allocator, cmd.line) catch return ExecuteError.OutOfMemory;
if (normalized.ptr != cmd.line.ptr) {
    self.expanded_strings.append(self.allocator, normalized) catch return ExecuteError.OutOfMemory;
}
const jake_expanded = self.expandJakeVariables(normalized) catch normalized;
```

- [ ] **Step 5: Verify normalization and executor tests**

Run the filtered executor tests. Expected: all line-continuation tests pass.

- [ ] **Step 6: Commit executor behavior**

```bash
git add src/executor.zig
git commit -m "fix(executor): normalize continued commands"
```

### Task 3: Preserve formatting and prove end-to-end execution

**Files:**

- Test: `src/formatter.zig`
- Create: `tests/e2e/fixtures/basic/line-continuation.jake`
- Modify: `tests/e2e/Jakefile`

**Interfaces:**

- Consumes: the source-backed multiline command slice from Task 1
- Produces: formatted Jakefiles that keep continuation line breaks and indentation

- [ ] **Step 1: Write a failing formatter regression**

Parse and format a recipe with two continued lines. Assert the output retains one backslash per break and remains parseable as one command.

- [ ] **Step 2: Run the formatter regression**

```bash
./scripts/zig test src/formatter.zig --test-filter "line continuation"
```

Expected: fail if continuation indentation is not emitted correctly.

- [ ] **Step 3: Retain source-backed multiline rendering**

Keep the existing `writer.print("    {s}\n", .{cmd.line})` production path. The parser's source-backed logical slice contains the continuation-line indentation, so the regression documents and protects the behavior without adding formatter code.

- [ ] **Step 4: Add the E2E fixture**

The fixture must prove argument joining and shared shell state:

```jake
task documented:
    echo "This is a very long command" \
         "that spans multiple lines"

task state:
    start=3000; p=$start; \
        p=$((p+1)); \
        echo "port=$p"
```

Add `test-basic` assertions for `This is a very long command that spans multiple lines`, `port=3001`, and dry-run output containing one normalized command.

- [ ] **Step 5: Build and run the focused E2E group**

```bash
./scripts/zig build
cd tests/e2e && ../../zig-out/bin/jake test-basic
```

Expected: all basic E2E checks pass.

- [ ] **Step 6: Commit formatter and E2E coverage**

```bash
git add src/formatter.zig tests/e2e/Jakefile tests/e2e/fixtures/basic/line-continuation.jake
git commit -m "test: cover command line continuation"
```

### Task 4: Update user-facing documentation

**Files:**

- Modify: `GUIDE.md`
- Modify: `docs/SYNTAX.md`
- Modify: `docs/TUTORIAL.md`
- Modify: `site/src/content/docs/docs/syntax.md`

**Interfaces:**

- Produces: consistent syntax reference and examples across all maintained documentation surfaces

- [ ] **Step 1: Document exact continuation rules**

State that the backslash must be the final character before LF/CRLF, the next line must be indented, indentation is removed, no separator is inserted, odd/even backslash runs differ, and the physical lines execute in one shell invocation.

- [ ] **Step 2: Add a practical tutorial example**

Show a multi-line command that shares a shell variable and explain why it remains one invocation.

- [ ] **Step 3: Verify examples and cross-document consistency**

```bash
rg -n -A18 -B2 "Line Continuation|line continuation" GUIDE.md docs/SYNTAX.md docs/TUTORIAL.md site/src/content/docs/docs/syntax.md
git diff --check
```

Expected: all four surfaces describe the same behavior and `git diff --check` is clean.

- [ ] **Step 4: Commit documentation**

```bash
git add GUIDE.md docs/SYNTAX.md docs/TUTORIAL.md site/src/content/docs/docs/syntax.md
git commit -m "docs: define line continuation semantics"
```

### Task 5: Review, verify, publish, and close the issue

**Files:**

- Review all files changed since `2eca881`

**Interfaces:**

- Produces: a reviewed, tested, pushed implementation and a closed GitHub issue #24

- [ ] **Step 1: Self-review the complete diff**

```bash
git diff 2eca881...HEAD
git diff --check 2eca881...HEAD
```

Check security, correctness, command-boundary edge cases, allocation cleanup, and unrelated changes.

- [ ] **Step 2: Run full quality gates with the compatible compiler**

```bash
./scripts/zig fmt --check src/
./scripts/zig build test
./scripts/zig build
./zig-out/bin/jake e2e
```

Expected: formatting clean; 0 unit-test failures; build succeeds; all E2E tests pass.

- [ ] **Step 3: Commit any review fixes**

Stage only files changed for issue #24 and use a conventional commit message.

- [ ] **Step 4: Rebase and push**

```bash
git pull --rebase
git push
git fetch --prune
git status --short --branch
```

Expected: `main...origin/main` with no working-tree changes.

- [ ] **Step 5: Close GitHub issue #24**

Close `HelgeSverre/jake#24` as completed only after the pushed commit and fresh quality-gate evidence are available.
