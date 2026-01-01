---
title: Migrating from Doit
description: Convert your dodo.py to a Jakefile.
tableOfContents:
  minHeadingLevel: 2
  maxHeadingLevel: 2
---

Doit (pydoit.org) is a Python-based build tool. If you're looking for a simpler, faster alternative, Jake provides similar functionality without requiring Python.

## Syntax Comparison

| Doit                | Jake                   |
| ------------------- | ---------------------- |
| `dodo.py`           | `Jakefile`             |
| `def task_name():`  | `task name:`           |
| `'actions': [...]`  | Indented commands      |
| `'file_dep': [...]` | Dependencies after `:` |
| `'targets': [...]`  | `file target:` recipe  |
| `'task_dep': [...]` | `[dependencies]`       |
| `'verbosity': 2`    | `-v` flag              |

## Basic Task Conversion

### Doit

```python
def task_build():
    """Build the application"""
    return {
        'actions': ['gcc -o app main.c'],
        'verbosity': 2,
    }
```

### Jake

```jake
# Build the application
task build:
    gcc -o app main.c
```

## File Dependencies

### Doit

```python
def task_compile():
    return {
        'file_dep': ['main.c', 'util.c'],
        'targets': ['app'],
        'actions': ['gcc -o app main.c util.c'],
        'clean': True,
    }
```

### Jake

```jake
file app: main.c util.c
    gcc -o app main.c util.c

task clean:
    rm -f app
```

Doit uses MD5 checksums; Jake also uses content-based tracking.

## Task Dependencies

### Doit

```python
def task_install():
    return {
        'actions': ['pip install -r requirements.txt'],
    }

def task_test():
    return {
        'task_dep': ['install'],
        'actions': ['pytest tests/'],
    }
```

### Jake

```jake
task install:
    pip install -r requirements.txt

task test: [install]
    pytest tests/
```

## Glob Patterns

### Doit

```python
from pathlib import Path

def task_bundle():
    return {
        'file_dep': list(Path('src').rglob('*.js')),
        'targets': ['dist/bundle.js'],
        'actions': ['esbuild src/index.js --bundle --outfile=dist/bundle.js'],
    }
```

### Jake

```jake
file dist/bundle.js: src/**/*.js
    esbuild src/index.js --bundle --outfile=dist/bundle.js
```

Jake has native glob support - no Python imports needed.

## Task Generators (Subtasks)

### Doit

```python
def task_compile():
    """Compile multiple files"""
    for src in ['foo.c', 'bar.c', 'baz.c']:
        obj = src.replace('.c', '.o')
        yield {
            'name': obj,
            'file_dep': [src],
            'targets': [obj],
            'actions': [f'gcc -c {src} -o {obj}'],
        }
```

### Jake

```jake
file foo.o: foo.c
    gcc -c foo.c -o foo.o

file bar.o: bar.c
    gcc -c bar.c -o bar.o

file baz.o: baz.c
    gcc -c baz.c -o baz.o
```

Or use `@each` for dynamic iteration:

```jake
task compile-all:
    @each foo.c bar.c baz.c
        gcc -c {{item}} -o {{item}}.o
    @end
```

## Parameters

### Doit

```python
def task_deploy():
    def deploy(env):
        print(f"Deploying to {env}")

    return {
        'actions': [deploy],
        'params': [{
            'name': 'env',
            'default': 'staging',
            'type': str,
        }],
    }
```

Usage: `doit deploy --env=production`

### Jake

```jake
task deploy env="staging":
    echo "Deploying to {{env}}"
```

Usage: `jake deploy env=production`

## Python Functions vs Shell

### Doit

```python
import datetime

def print_time():
    print(datetime.datetime.now())

def task_timestamp():
    return {
        'actions': [print_time],
        'verbosity': 2,
    }
```

### Jake

```jake
task timestamp:
    date
```

For complex logic, call a Python script:

```jake
task process-data:
    python scripts/process.py
```

## Configuration

### Doit

```python
DOIT_CONFIG = {
    'default_tasks': ['build', 'test'],
    'verbosity': 2,
}
```

### Jake

```jake
@default
task all: [build, test]
    echo "Done"
```

Use CLI flags for verbosity: `jake -v`

## Complete Migration Example

### Before (dodo.py)

```python
from pathlib import Path

DOIT_CONFIG = {
    'default_tasks': ['build'],
}

def task_clean():
    """Remove build artifacts"""
    return {
        'actions': ['rm -rf build/ dist/'],
    }

def task_install():
    """Install dependencies"""
    return {
        'file_dep': ['requirements.txt'],
        'actions': ['pip install -r requirements.txt'],
    }

def task_build():
    """Build the application"""
    return {
        'task_dep': ['install'],
        'file_dep': list(Path('src').rglob('*.py')),
        'targets': ['dist/app.pyz'],
        'actions': [
            'mkdir -p dist',
            'python -m zipapp src -o dist/app.pyz',
        ],
        'clean': True,
    }

def task_test():
    """Run tests"""
    return {
        'task_dep': ['install'],
        'actions': ['pytest tests/ -v'],
        'verbosity': 2,
    }

def task_deploy():
    """Deploy to server"""
    def do_deploy(env):
        print(f"Deploying to {env}...")

    return {
        'task_dep': ['build', 'test'],
        'actions': [do_deploy],
        'params': [{
            'name': 'env',
            'default': 'staging',
        }],
    }
```

### After (Jakefile)

```jake
@default
task build: [install, dist/app.pyz]
    @desc "Build the application"

task clean:
    @desc "Remove build artifacts"
    rm -rf build/ dist/

task install:
    @desc "Install dependencies"
    @cache requirements.txt
    pip install -r requirements.txt

file dist/app.pyz: src/**/*.py
    mkdir -p dist
    python -m zipapp src -o dist/app.pyz

task test: [install]
    @desc "Run tests"
    pytest tests/ -v

task deploy env="staging": [build, test]
    @desc "Deploy to server"
    echo "Deploying to {{env}}..."
    ./deploy.sh {{env}}
```

## CLI Comparison

| Doit                | Jake                 |
| ------------------- | -------------------- |
| `doit`              | `jake`               |
| `doit list`         | `jake --list`        |
| `doit build`        | `jake build`         |
| `doit clean`        | `jake clean`         |
| `doit -n`           | `jake -n`            |
| `doit --parallel 4` | `jake -j4`           |
| `doit forget`       | Clear `.jake/` cache |

## Key Differences

| Feature             | Doit           | Jake                 |
| ------------------- | -------------- | -------------------- |
| **Language**        | Python         | Zig (single binary)  |
| **Config**          | Python code    | Simple DSL           |
| **Dependencies**    | MD5 checksum   | Checksum-based       |
| **Actions**         | Python + shell | Shell (call scripts) |
| **Task generators** | `yield`        | Manual or `@each`    |
| **Setup**           | `pip install`  | Single binary        |

## What You Gain

1. **No Python dependency** - Single binary, works anywhere
2. **Simpler syntax** - No Python boilerplate
3. **Faster startup** - No interpreter initialization
4. **Built-in watch mode** - `jake -w build`
5. **Native globs** - No `pathlib` imports

## What You Lose

1. **Python functions** - Must use shell or call scripts
2. **Complex logic in tasks** - Move to external scripts
3. **`getargs` value passing** - Use environment variables
4. **Custom uptodate checks** - Use `@cache` patterns

## See Also

- [File Targets](/docs/file-targets/) - Jake's dependency tracking
- [Conditionals](/docs/conditionals/) - Logic in recipes
- [Variables](/docs/variables/) - Variable expansion
