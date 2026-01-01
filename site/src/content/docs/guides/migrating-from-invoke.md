---
title: Migrating from Invoke
description: Convert your tasks.py to a Jakefile.
tableOfContents:
  minHeadingLevel: 2
  maxHeadingLevel: 2
---

Invoke (pyinvoke.org) is a Python library for managing shell tasks. Jake provides similar functionality without requiring Python.

## Syntax Comparison

| Invoke             | Jake           |
| ------------------ | -------------- |
| `tasks.py`         | `Jakefile`     |
| `@task` decorator  | `task name:`   |
| `c.run("cmd")`     | Direct command |
| `@task(pre=[dep])` | `[dep]`        |
| `invoke task`      | `jake task`    |

## Basic Task Conversion

### Invoke

```python
from invoke import task

@task
def build(c):
    """Build the application"""
    c.run("go build -o app")
```

### Jake

```jake
# Build the application
task build:
    go build -o app
```

## Dependencies

### Invoke

```python
from invoke import task

@task
def clean(c):
    c.run("rm -rf dist/")

@task
def install(c):
    c.run("pip install -r requirements.txt")

@task(pre=[clean, install])
def build(c):
    c.run("python setup.py build")
```

### Jake

```jake
task clean:
    rm -rf dist/

task install:
    pip install -r requirements.txt

task build: [clean, install]
    python setup.py build
```

## Parameters

### Invoke

```python
from invoke import task

@task
def deploy(c, env="staging", force=False):
    """Deploy to environment"""
    cmd = f"./deploy.sh {env}"
    if force:
        cmd += " --force"
    c.run(cmd)
```

Usage: `invoke deploy --env=production --force`

### Jake

```jake
task deploy env="staging" force="":
    @desc "Deploy to environment"
    @if eq({{force}}, "true")
        ./deploy.sh {{env}} --force
    @else
        ./deploy.sh {{env}}
    @end
```

Usage: `jake deploy env=production force=true`

## Boolean Flags

### Invoke

```python
@task
def test(c, verbose=False, coverage=False):
    cmd = "pytest"
    if verbose:
        cmd += " -v"
    if coverage:
        cmd += " --cov"
    c.run(cmd)
```

### Jake

```jake
task test verbose="" coverage="":
    @if eq({{verbose}}, "true")
        @if eq({{coverage}}, "true")
            pytest -v --cov
        @else
            pytest -v
        @end
    @else
        @if eq({{coverage}}, "true")
            pytest --cov
        @else
            pytest
        @end
    @end
```

Or simpler with positional args:

```jake
task test:
    pytest {{$@}}
```

Usage: `jake test -v --cov`

## Namespaces (Collections)

### Invoke

```python
from invoke import task, Collection

@task
def build(c):
    c.run("docker build -t myapp .")

@task
def push(c):
    c.run("docker push myapp")

docker = Collection("docker")
docker.add_task(build)
docker.add_task(push)

ns = Collection()
ns.add_collection(docker)
```

Usage: `invoke docker.build`

### Jake

```jake
# docker.jake
task build:
    docker build -t myapp .

task push:
    docker push myapp
```

```jake
# Jakefile
@import "docker.jake" as docker

task release: [docker.build, docker.push]
    echo "Released!"
```

Usage: `jake docker.build`

## Context and Configuration

### Invoke

```python
from invoke import task, Config

config = Config(defaults={
    "app": {"name": "myapp", "port": 8080}
})

@task
def run(c):
    c.run(f"./server --port {c.config.app.port}")
```

### Jake

```jake
app_name = "myapp"
port = "8080"

task run:
    ./server --port {{port}}
```

With environment files:

```jake
@dotenv

task run:
    ./server --port $PORT
```

## Error Handling

### Invoke

```python
@task
def deploy(c):
    result = c.run("./deploy.sh", warn=True)
    if result.failed:
        print("Deploy failed, rolling back...")
        c.run("./rollback.sh")
```

### Jake

```jake
task deploy:
    @ignore
    ./deploy.sh || ./rollback.sh
```

Or with hooks:

```jake
@on_error ./rollback.sh

task deploy:
    ./deploy.sh
```

## Working Directory

### Invoke

```python
@task
def build_frontend(c):
    with c.cd("frontend"):
        c.run("npm run build")
```

### Jake

```jake
task build-frontend:
    @cd frontend
    npm run build
```

## Environment Variables

### Invoke

```python
@task
def build(c):
    c.run("go build", env={"CGO_ENABLED": "0"})
```

### Jake

```jake
task build:
    CGO_ENABLED=0 go build
```

Or globally:

```jake
@export CGO_ENABLED=0

task build:
    go build
```

## Complete Migration Example

### Before (tasks.py)

```python
from invoke import task, Collection

@task
def clean(c):
    """Remove build artifacts"""
    c.run("rm -rf dist/ build/ *.egg-info")

@task
def install(c):
    """Install dependencies"""
    c.run("pip install -r requirements.txt")

@task(pre=[install])
def build(c):
    """Build the package"""
    c.run("python setup.py build")

@task(pre=[build])
def test(c, verbose=False):
    """Run tests"""
    cmd = "pytest tests/"
    if verbose:
        cmd += " -v"
    c.run(cmd)

@task(pre=[test])
def deploy(c, env="staging"):
    """Deploy to environment"""
    if env == "production":
        if not input("Deploy to PRODUCTION? (yes/no): ") == "yes":
            return
    c.run(f"./deploy.sh {env}")

# Docker namespace
@task
def docker_build(c):
    c.run("docker build -t myapp .")

@task
def docker_push(c):
    c.run("docker push myapp")

docker = Collection("docker")
docker.add_task(docker_build, "build")
docker.add_task(docker_push, "push")

ns = Collection()
ns.add_task(clean)
ns.add_task(install)
ns.add_task(build)
ns.add_task(test)
ns.add_task(deploy)
ns.add_collection(docker)
```

### After (Jakefile)

```jake
task clean:
    @desc "Remove build artifacts"
    rm -rf dist/ build/ *.egg-info

task install:
    @desc "Install dependencies"
    pip install -r requirements.txt

task build: [install]
    @desc "Build the package"
    python setup.py build

task test verbose="": [build]
    @desc "Run tests"
    @if eq({{verbose}}, "true")
        pytest tests/ -v
    @else
        pytest tests/
    @end

task deploy env="staging": [test]
    @desc "Deploy to environment"
    @if eq({{env}}, "production")
        @confirm "Deploy to PRODUCTION?"
    @end
    ./deploy.sh {{env}}

@group docker
task docker-build:
    @desc "Build Docker image"
    docker build -t myapp .

@group docker
task docker-push:
    @desc "Push Docker image"
    docker push myapp
```

## CLI Comparison

| Invoke                     | Jake                   |
| -------------------------- | ---------------------- |
| `invoke`                   | `jake`                 |
| `invoke build`             | `jake build`           |
| `invoke -l`                | `jake --list`          |
| `invoke deploy --env=prod` | `jake deploy env=prod` |
| `invoke docker.build`      | `jake docker-build`    |
| `invoke -e`                | Uses environment       |

## Key Differences

| Feature           | Invoke         | Jake                  |
| ----------------- | -------------- | --------------------- |
| **Language**      | Python         | DSL                   |
| **Dependencies**  | pip install    | Single binary         |
| **File tracking** | Manual         | Native `file` recipes |
| **Parallel**      | Manual threads | `-j` flag             |
| **Watch mode**    | External tool  | Built-in              |

## What You Gain

1. **No Python dependency** - Single binary
2. **File dependency tracking** - Built-in
3. **Parallel execution** - `-j` flag
4. **Watch mode** - `jake -w`
5. **Faster startup** - No interpreter

## What You Lose

1. **Python flexibility** - Move complex logic to scripts
2. **Programmatic access** - No Python API
3. **Fabric integration** - Use shell commands

## See Also

- [Variables](/docs/variables/) - Configuration
- [Conditionals](/docs/conditionals/) - Logic in recipes
- [Imports](/docs/imports/) - Namespacing
