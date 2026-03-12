---
title: Positional Arguments
description: Pass arguments directly to recipes using positional syntax.
---

Positional arguments let you pass values to recipes without named parameters.

## Basic Usage

Access arguments with `{{$1}}`, `{{$2}}`, etc.:

```jake
task greet:
    echo "Hello, {{$1}}!"
```

```bash
$ jake greet World
Hello, World!
```

## Multiple Arguments

Access each argument by position:

```jake
task deploy:
    echo "Deploying {{$1}} to {{$2}}"
```

```bash
$ jake deploy v1.0.0 production
Deploying v1.0.0 to production
```

## All Arguments

Use `{{$@}}` to access all arguments at once:

```jake
task echo-all:
    echo "Arguments: {{$@}}"
```

```bash
$ jake echo-all a b c d
Arguments: a b c d
```

## With Named Parameters

Positional arguments work alongside named parameters:

```jake
task deploy env="staging":
    echo "Deploying to {{env}} with args: {{$@}}"
```

```bash
$ jake deploy env=production extra-flag
Deploying to production with args: extra-flag
```

## Forwarding to Commands

Pass all arguments to another command:

```jake
task npm:
    npm {{$@}}
```

```bash
$ jake npm install lodash
# Runs: npm install lodash
```

## Conditional Logic on Arguments

Positional args (`{{$1}}`, `{{$2}}`) do not work inside `@if` condition expressions. Condition strings are not pre-expanded, so `eq("{{$1}}", "")` looks up a variable literally named `$1` (not found), always resolves to empty string, and makes the condition useless.

**Use named parameters instead.** Named parameters are stored in the variables map and work correctly with all condition functions:

```jake
# Works: named parameter used in condition
task greet name="stranger":
    @if eq(name, stranger)
        echo "No name given, using default"
    @else
        echo "Hello, {{name}}!"
    @end
```

```bash
$ jake greet
No name given, using default

$ jake greet name=Alice
Hello, Alice!
```

Named parameters also support `eq()`, `neq()`, `exists()`, and any other condition function.

## Syntax Notes

- Use `{{$1}}`, `{{$2}}`, etc. for specific positions (1-indexed)
- Use `{{$@}}` for all arguments as a single string
- Do not add spaces inside braces - `{{$1}}` works, `{{ $1 }}` does not
- Arguments are whitespace-separated on the command line

## See Also

- [Variables](/docs/variables/) - Named variable expansion
- [Tasks](/docs/tasks/) - Recipe parameters with defaults
