# Fuzzing Jake

Jake uses Zig's built-in coverage-guided fuzzing for testing the lexer, parser, and other components.

## Quick Start

```bash
# Run fuzz tests with coverage guidance
zig build fuzz --fuzz

# Or use the jake task (opens web UI on port 8080)
jake fuzz
```

The fuzzer will run indefinitely, exploring code paths and looking for crashes. Press `Ctrl+C` to stop.

## How It Works

Zig's integrated fuzzer provides:

- **Coverage-guided mutations** - Keeps inputs that reach new code paths
- **Automatic corpus management** - No manual seed files needed
- **Web interface** - Visualize which code paths have been tested
- **LLVM instrumentation** - Uses the same tech as libFuzzer/AFL++

This is much more effective than "dumb" random fuzzing because the fuzzer learns which inputs are interesting.

## Fuzz Targets

Fuzz tests are embedded in the source files using `std.testing.fuzz`:

| Component | File | What it tests |
|-----------|------|---------------|
| Lexer | `src/lexer.zig` | Token parsing from arbitrary input |
| Parser | `src/parser.zig` | AST construction from fuzzed source |
| Glob | `src/glob.zig` | Pattern matching and parsing |
| Functions | `src/functions.zig` | Built-in function evaluation |
| Conditions | `src/conditions.zig` | @if/@elif condition evaluation |
| Formatter | `src/formatter.zig` | Round-trip formatting (parse → format → parse) |
| Args | `src/args.zig` | CLI argument parsing, flag suggestion |
| Suggest | `src/suggest.zig` | Levenshtein distance, typo suggestions |
| Env | `src/env.zig` | .env file parsing |

## Web Interface

The `--fuzz` flag automatically enables a web interface. View coverage in real-time:

```bash
zig build fuzz --fuzz
# Web UI starts automatically - check terminal for URL (e.g., http://[::1]:58415/)
```

Open the URL shown in the terminal in your browser. The interface shows:
- Source code with coverage markers (red = not hit, green = hit)
- Live-updating statistics
- Which code paths the fuzzer has explored

## What Gets Tested

**Covered:**
- Lexer tokenization (all token types, edge cases)
- Parser AST construction and error handling
- Formatter round-trip stability (idempotent formatting)
- Glob pattern matching logic
- Built-in function parsing and evaluation
- Condition expression evaluation
- CLI argument parsing and validation
- Levenshtein distance for typo suggestions
- .env file parsing

**Not covered (by design):**
- Recipe execution (would run shell commands)
- File I/O operations
- Network operations

## Interpreting Results

- **No output** = Tests passing, fuzzer is exploring
- **Crash/panic** = Bug found - investigate the failing input
- **Memory leak** = Zig's allocator will report on exit

When a crash is found:

1. The fuzzer will print the failing input
2. Re-run with that specific input to reproduce
3. Debug using `zig build test` with the failing case

## Adding New Fuzz Targets

To fuzz a new component, add a test using `std.testing.fuzz`:

```zig
test "fuzz my_function" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) !void {
            // Call the function with fuzzed input
            // Errors are expected - just don't crash
            my_function(input) catch {};
        }
    }.testOne, .{});
}
```

The API takes:
- A context value (use `{}` for no context)
- A test function that receives the context and fuzz input bytes
- Options (use `.{}` for defaults)

Guidelines:
- Use `catch {}` or `catch return` for expected errors
- Only crashes/panics indicate bugs
- Avoid side effects (file I/O, network, shell commands)
- Use `std.testing.allocator` for leak detection

## Memory Leak Detection

Zig's `GeneralPurposeAllocator` reports leaks automatically. If you see:

```
error(gpa): memory address 0x... leaked
```

That indicates an allocation that was never freed - a real bug to fix.

## Requirements

- Zig 0.15.2 or later (has integrated fuzzing support)
- No external tools needed (AFL++, honggfuzz, etc. are not required)
