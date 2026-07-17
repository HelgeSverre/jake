# Jake CLI Argument Grammar

This document specifies how `jake` parses its command line: how it decides what
is a flag, what is the recipe, and what is a recipe argument. The parser lives in
`src/cli/args.zig` (`Args.parse` / `Args.parseTracked`; `main.zig` uses `parseTracked`
so parse errors can name the offending argument).

The guiding principle is that **flag position does not matter** — jake's global
flags may appear before or after the recipe name, interspersed with recipe
arguments, the way `clap` and most other unix programs behave.

## Grammar

```
jake [ <token> ... ] [ -- <literal-arg> ... ]
```

A `<token>` is classified in a single left-to-right pass:

1. **`--` (bare double dash)** — a hard separator. Every token after it is
   treated literally (recipe name if none yet, otherwise a recipe argument);
   no further flag parsing happens.
2. **A flag-like token** — starts with `-` and has at least one more character
   (`isFlagLike`). Bare `-` is _not_ flag-like; it is a positional (the stdin
   convention).
3. **A bare token** — the first bare token becomes the **recipe name**; every
   later bare token is a **recipe positional argument**.

### Flag forms (accepted anywhere on the line)

| Form                 | Example                     | Meaning                                      |
| -------------------- | --------------------------- | -------------------------------------------- |
| Long                 | `--verbose`                 | Boolean / value-less flag                    |
| Long with value      | `--jakefile Jakefile.ci`    | Value in the next token                      |
| Long inline value    | `--jakefile=Jakefile.ci`    | Value after `=`                              |
| Negatable            | `--no-verbose`              | Negated form of a `negatable` flag           |
| Short                | `-v`                        | Single short flag                            |
| Combined short       | `-vn`                       | Several value-less short flags               |
| Countable            | `-vvv`                      | Repeats a countable flag (verbosity level 3) |
| Attached short value | `-fFILE`, `-j4`, `-sRECIPE` | Value attached to the flag                   |

### Recipe arguments

Everything that reaches the recipe is carried in `positional`, addressable inside
recipe bodies as `{{$1}}`, `{{$2}}`, `{{$@}}`, and — for `name=value` tokens — as
named parameters. See `docs/SYNTAX.md` §5.4 and §5.5.

## Rules

- **Known jake flags are always consumed by jake**, whether they appear before or
  after the recipe name. `jake build --jakefile other.jake` sets the jakefile;
  it does not pass `--jakefile other.jake` to `build`.
- **The first bare token is the recipe; the rest are its arguments.**
  `jake deploy prod fast` → recipe `deploy`, args `prod fast`.
- **`--` stops flag parsing.** Use it to pass a flag-like argument to the recipe:
  `jake run -- --port 8080` runs `run` with the literal args `--port 8080`.
- **Unknown flag _before_ the recipe is an error** (with a "did you mean?"
  suggestion): `jake --prot 8080 serve` → error.
- **Unknown flag _after_ the recipe is forwarded to the recipe** as a positional
  argument. Because jake recipes commonly wrap arbitrary tools, `jake test --foo`
  forwards `--foo` to whatever `test` invokes. (Trade-off: a mistyped jake flag
  placed after the recipe is not caught — it is forwarded.)
- **`-s` / `--show` is recipe-derived.** With no explicit value it shows the
  recipe positional, so `jake --show pkg.dev`, `jake -s pkg.dev`, and
  `jake pkg.dev --show` are equivalent. An explicit value still works via the
  attached/inline form: `jake --show=pkg.dev` or `-spkg.dev`.

### Edge cases

- **A value-less flag given an inline value is an error.** `--yes=false` and
  `--verbose=3` report _"Option … does not take a value"_ rather than silently
  ignoring the value (which would make `--yes=false` mean `yes=true`). Use
  `--no-yes` / `--no-verbose` to negate, and `-vvv` for verbosity levels.
- **A value-taking short flag consumes the rest of its token as the value.**
  `-sbuild` and `-sv` set `--show`'s value to `build`/`v` (getopt convention);
  a value-taking flag cannot sit in the middle of a combined group (`-vf` is an
  error — write `-v -f FILE`).
- **A combined short token that isn't fully valid is forwarded whole after the
  recipe.** `jake build -vx` (where `x` is unknown) forwards `-vx` to the recipe
  verbatim rather than applying `-v` and then failing — no partial application.
- **Only the first `--` is a separator.** A later `--` is a literal argument.

### Optional-value flags

`-j/--jobs`, `-w/--watch`, `--completions`, and `--external` take an _optional_
value. Whether they consume the following token depends on the flag:

- `--jobs` consumes the next token only if it parses as an integer, else it
  defaults to the CPU count and leaves the token for the recipe
  (`jake -j build` → CPU-count jobs, recipe `build`).
- `--watch` consumes the next token only if it looks like a glob pattern
  (contains `*` or `?`).
- `--completions` / `--external` consume the next token only if it is a valid
  choice (`bash|zsh|fish`, `make|just`); a provided non-flag token that is not a
  valid choice is an error.

## Divergences fixed by the 2026 rewrite

Before the single-pass rewrite, `src/cli/args.zig` had **two separate parsing paths**
— one before the recipe name and a weaker one after it — which produced several
surprising, position-dependent bugs:

- **Required-value flags after the recipe were silently dropped.**
  `jake pkg.dev --show` treated `--show` as a recipe argument and _ran_ `pkg.dev`
  instead of showing it. The same happened to `-f`, `--group`, `--filter`,
  `--type`, and `--port` after a recipe.
- **No `=` splitting after the recipe.** `jake build --jakefile=x` after a recipe
  was passed through verbatim rather than parsed.
- **Inconsistent errors.** Unknown/invalid flags errored before the recipe but
  were silently swallowed after it.
- **Silent allocation failure.** Positional collection used
  `append(...) catch {}`, discarding arguments on OOM. The rewrite propagates the
  error instead.
- **Dead validation metadata.** Each flag's `choices`/`validator` fields were
  declared but ignored; validation was hardcoded in per-flag helpers. They are
  now the single source of value validation.

The rewrite collapses the two paths into one clap-style pass and drives all
flag→field assignment, negation, and env-var fallback from a single declarative
`Bind` descriptor on each flag (`src/cli/args.zig`).
