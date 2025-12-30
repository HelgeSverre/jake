---
title: Troubleshooting
description: Common errors and how to fix them.
---

## Recipe Not Found

```
error: Recipe 'foo' not found
Run 'jake --list' to see available recipes.
```

**Causes:**
- Typo in recipe name
- Jakefile not in current directory
- Recipe is private (prefixed with `_`)

**Solutions:**
- Check spelling - Jake suggests similar names if you're close
- Use `jake --list` to see available recipes
- Use `-f` to specify Jakefile path: `jake -f path/to/Jakefile`

## Cyclic Dependency

```
error: Cyclic dependency detected in 'foo'
```

**Cause:** Recipes depend on each other in a loop:

```jake
# Wrong!
task a: [b]
task b: [a]
```

**Solution:** Break the cycle by restructuring dependencies:

```jake
task shared-setup:
    # Common setup

task a: [shared-setup]
    # A's work

task b: [shared-setup]
    # B's work
```

## Command Failed

```
error: command exited with code 1
```

**Cause:** A shell command returned a non-zero exit code.

**Solutions:**
- Run with `-v` (verbose) to see the failing command
- Run with `-n` (dry-run) to see commands without executing
- Use `@ignore` to continue on failure if appropriate:

```jake
task cleanup:
    @ignore
    rm -rf temp/     # Won't stop if this fails
    rm -rf cache/
```

## No Jakefile Found

```
error: No Jakefile found
```

**Cause:** No `Jakefile` in current directory or parent directories.

**Solutions:**
- Create a `Jakefile` in your project root
- Use `-f` to specify the path: `jake -f scripts/Jakefile`

## Missing Required Environment Variable

```
error: Required environment variable 'API_KEY' is not set
```

**Cause:** A `@require` directive specifies a variable that isn't set.

**Solutions:**
- Set the variable: `export API_KEY=xxx`
- Create a `.env` file and add `@dotenv` to your Jakefile
- Pass it inline: `API_KEY=xxx jake deploy`

## Missing Required Command

```
error: Command 'docker' not found
Hint: Install Docker from https://docker.com
```

**Cause:** A `@needs` directive specifies a command that isn't installed.

**Solutions:**
- Install the missing command
- Check that it's in your PATH
- If auto-install is configured, run the suggested task

## File Target Never Rebuilds

**Cause:** File target might have incorrect dependencies.

**Check:**
1. Verify glob patterns match your files:
   ```bash
   jake -v build  # Verbose shows matched files
   ```
2. Ensure the output file path matches the recipe name exactly
3. Check that source files are actually being modified

## File Target Always Rebuilds

**Cause:** Output file might be missing or dependencies misconfigured.

**Check:**
1. Verify the output file exists after build
2. Ensure recipe creates the file at the exact path specified
3. Check for typos in file paths

## Watch Mode Not Detecting Changes

**Cause:** Watch patterns might not match your files.

**Solutions:**
- Add explicit `@watch` patterns:
  ```jake
  task build:
      @watch src/**/*.ts
      npm run build
  ```
- Check that file system events are working (some editors use atomic saves)
- Try more specific patterns

## Parallel Execution Issues

**Cause:** Tasks that should be sequential are running in parallel.

**Solution:** Ensure dependencies are correctly specified:

```jake
# This ensures compile runs before bundle
task compile:
    tsc

task bundle: [compile]  # Depends on compile
    esbuild dist/index.js

task build: [bundle]
    echo "Done"
```

## Getting Help

If you're still stuck:

1. Run with `-v` for verbose output
2. Run with `-n` for dry-run to see what would execute
3. Check [GitHub Issues](https://github.com/HelgeSverre/jake/issues)
4. Use `jake -s recipe` to inspect a recipe's full definition

```bash
jake -s deploy
# Shows: type, dependencies, parameters, commands, hooks
```
