# Fuzzing Jake

This repo includes a small fuzz harness for hardening Jake's **lexer/parser** without executing any recipe commands.

The harness lives at `src/fuzz_parse.zig` and is intended to be driven by a fuzzer while compiled with Zig's `-ffuzz` instrumentation.

## Goals

- Shake out parser crashes, panics, OOM handling bugs
- Catch memory safety issues early (use Zig safety + sanitizers)
- Build a small, reusable corpus of "interesting" Jakefile inputs

## Requirements

- Zig `0.15.x` (this repo currently builds with `0.15.2`)
- Optional (for advanced fuzzing):
  - AFL++: `brew install afl++` (macOS) or https://github.com/AFLplusplus/AFLplusplus
  - honggfuzz: https://github.com/google/honggfuzz (Linux only)

## Build the fuzz target

Preferred (via `build.zig`):

```sh
zig build fuzz-parse -Doptimize=ReleaseSafe
```

Manual (no build step):

```sh
zig build-exe -OReleaseSafe -ffuzz \
  --dep jake \
  -Mroot=src/fuzz_parse.zig \
  -Mjake=src/root.zig \
  -femit-bin=zig-out/bin/jake-fuzz-parse
```

Notes:

- `-ffuzz` enables fuzzing-oriented instrumentation.
- `-OReleaseSafe` keeps Zig safety checks (recommended for fuzzing).

## Sanity run (no fuzzer)

Run it on an existing Jakefile:

```sh
./zig-out/bin/jake-fuzz-parse Jakefile
```

Or via stdin:

```sh
./zig-out/bin/jake-fuzz-parse < Jakefile
```

Expected behavior:

- Exit code `0` for inputs that successfully parse.
- Exit code `0` for inputs that fail parsing (the harness treats parse errors as non-crashes and returns).
- Any crash/panic/assert is a bug worth investigating.

## Quick start (no external fuzzer needed)

The repo includes a simple "dumb fuzzer" script that works on any system:

```sh
# Run 1000 iterations (default)
just fuzz

# Or with jake
./zig-out/bin/jake fuzz

# Or directly with custom iteration count
./scripts/dumb-fuzz.sh 5000
```

This mutates corpus files randomly and looks for crashes. No external tools required.

## Run with AFL++ (more thorough than dumb fuzzer)

AFL++ is available on macOS via Homebrew:

```sh
brew install afl++
```

Then run:

```sh
just fuzz-afl
# or
./zig-out/bin/jake fuzz-afl
```

**Note:** We run AFL++ in "dumb mode" (`-n` flag) because Zig's `-ffuzz` instrumentation is not compatible with AFL++'s coverage format. This means AFL++ won't get coverage feedback, but it still provides:

- Better mutation strategies than our shell script
- Proper crash detection and minimization
- Hang detection
- Parallel fuzzing support

For full coverage-guided fuzzing, you would need to compile with `afl-clang-fast` which requires a C wrapper - not practical for a Zig project.

Manual setup:

```sh
mkdir -p corpus findings
cp Jakefile corpus/
find samples -name "Jakefile" -exec cp {} corpus/ \;
find samples -name "*.jake" -exec cp {} corpus/ \;
AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
  afl-fuzz -n -i corpus -o findings -- ./zig-out/bin/jake-fuzz-parse @@
```

Where `@@` is AFL++ placeholder for the current mutated input file.

## Run with honggfuzz (Linux only)

honggfuzz is not available via Homebrew on macOS, but works well on Linux:

```sh
honggfuzz -i corpus -o findings -- ./zig-out/bin/jake-fuzz-parse ___FILE___
```

## Triage workflow

When a fuzzer reports a crash:

1) Re-run the harness on the crashing input:

```sh
./zig-out/bin/jake-fuzz-parse findings/crashes/<file>
```

2) Rebuild with extra diagnostics (optional):

- Add more debug info: `-ODebug`
- Increase reference traces: `-freference-trace=20`

3) Reduce the crashing input:

Most fuzzers do this automatically (minimization). If not, manually delete chunks until the minimal reproducer remains.

## What this fuzz target covers (and does not)

Covers:

- Lexer/tokenization paths
- Parser/AST construction
- AST deinit paths (important for leak detection)

Does not cover:

- Recipe execution / shell commands
- Import resolution
- Watch mode

Those can be fuzzed too, but should be done with separate harnesses that sandbox I/O and avoid executing arbitrary commands.

## Suggested next fuzz targets

If you want to expand fuzzing beyond parsing, good next steps are:

- Import resolution:
  - feed a temp directory with multiple Jakefiles
  - fuzz `@import` graphs for recursion/cycle edge cases

- Variable expansion engine:
  - fuzz strings containing `{{var}}` and built-in function calls

- Glob expansion:
  - fuzz patterns passed into `glob.expandGlob` with a controlled temp filesystem tree

## Memory leak checks

Zig's `GeneralPurposeAllocator` can report leaks on process exit.

A regression we recently fixed was a leak in parallel execution variable expansion. A quick check is:

```sh
./zig-out/bin/jake -j4 -n all
```

If you see `error(gpa): ... leaked`, that is a real allocation that was not freed.
