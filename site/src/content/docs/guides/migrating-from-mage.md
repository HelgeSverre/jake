---
title: Migrating from Mage
description: Convert your magefile.go to a Jakefile.
tableOfContents:
  minHeadingLevel: 2
  maxHeadingLevel: 2
---

Mage (magefile.org) uses Go functions as build tasks. Jake provides similar functionality with a simpler DSL that doesn't require compiling.

## Syntax Comparison

| Mage               | Jake           |
| ------------------ | -------------- |
| `magefile.go`      | `Jakefile`     |
| `func Build()`     | `task build:`  |
| `mg.Deps(Install)` | `[install]`    |
| `sh.Run(...)`      | Direct command |
| `//go:build mage`  | Not needed     |

## Basic Task Conversion

### Mage

```go
//go:build mage

package main

import "github.com/magefile/mage/sh"

// Build compiles the application
func Build() error {
    return sh.Run("go", "build", "-o", "app", ".")
}
```

### Jake

```jake
# Build compiles the application
task build:
    go build -o app .
```

## Dependencies

### Mage

```go
import "github.com/magefile/mage/mg"

func Build() error {
    mg.Deps(Install, Generate)
    return sh.Run("go", "build", "-o", "app")
}

func Install() error {
    return sh.Run("go", "mod", "download")
}

func Generate() error {
    return sh.Run("go", "generate", "./...")
}
```

### Jake

```jake
task build: [install, generate]
    go build -o app

task install:
    go mod download

task generate:
    go generate ./...
```

## Error Handling

### Mage

```go
func Deploy() error {
    if err := Build(); err != nil {
        return fmt.Errorf("build failed: %w", err)
    }
    if err := sh.Run("rsync", "-avz", "dist/", "server:/app/"); err != nil {
        return err
    }
    return nil
}
```

### Jake

```jake
task deploy: [build]
    rsync -avz dist/ server:/app/
```

Jake automatically stops on command failure.

## Environment Variables

### Mage

```go
func Build() error {
    env := map[string]string{
        "CGO_ENABLED": "0",
        "GOOS":        "linux",
    }
    return sh.RunWith(env, "go", "build", "-o", "app")
}
```

### Jake

```jake
task build:
    CGO_ENABLED=0 GOOS=linux go build -o app
```

Or use `@export`:

```jake
@export CGO_ENABLED=0

task build:
    GOOS=linux go build -o app
```

## Conditional Logic

### Mage

```go
import "runtime"

func Install() error {
    if runtime.GOOS == "darwin" {
        return sh.Run("brew", "install", "deps")
    }
    return sh.Run("apt-get", "install", "deps")
}
```

### Jake

```jake
@platform macos
task install:
    brew install deps

@platform linux
task install:
    apt-get install deps
```

## File Operations

### Mage

```go
import "github.com/magefile/mage/sh"

func Clean() error {
    return sh.Rm("dist")
}

func Prepare() error {
    return os.MkdirAll("dist", 0755)
}
```

### Jake

```jake
task clean:
    rm -rf dist

task prepare:
    mkdir -p dist
```

## Verbose/Debug Output

### Mage

```go
import "github.com/magefile/mage/mg"

func Build() error {
    if mg.Verbose() {
        fmt.Println("Building with verbose output...")
    }
    return sh.Run("go", "build", "-v", "-o", "app")
}
```

### Jake

```jake
task build:
    @if is_verbose()
        echo "Building with verbose output..."
        go build -v -o app
    @else
        go build -o app
    @end
```

## Namespaced Targets

### Mage

```go
type Docker mg.Namespace

func (Docker) Build() error {
    return sh.Run("docker", "build", "-t", "myapp", ".")
}

func (Docker) Push() error {
    return sh.Run("docker", "push", "myapp")
}
```

Usage: `mage docker:build`

### Jake

Using imports:

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

## Complete Migration Example

### Before (magefile.go)

```go
//go:build mage

package main

import (
    "fmt"
    "os"
    "github.com/magefile/mage/mg"
    "github.com/magefile/mage/sh"
)

var Default = Build

// Install downloads dependencies
func Install() error {
    fmt.Println("Installing dependencies...")
    return sh.Run("go", "mod", "download")
}

// Build compiles the application
func Build() error {
    mg.Deps(Install)
    fmt.Println("Building...")
    env := map[string]string{"CGO_ENABLED": "0"}
    return sh.RunWith(env, "go", "build", "-o", "bin/app", "./cmd/app")
}

// Test runs the test suite
func Test() error {
    mg.Deps(Build)
    return sh.Run("go", "test", "-v", "./...")
}

// Clean removes build artifacts
func Clean() error {
    fmt.Println("Cleaning...")
    return sh.Rm("bin")
}

type Docker mg.Namespace

// Build builds the Docker image
func (Docker) Build() error {
    mg.Deps(Build)
    return sh.Run("docker", "build", "-t", "myapp:latest", ".")
}

// Push pushes to registry
func (Docker) Push() error {
    return sh.Run("docker", "push", "myapp:latest")
}
```

### After (Jakefile)

```jake
@export CGO_ENABLED=0

@default
task build: [install]
    @desc "Build the application"
    @pre echo "Building..."
    go build -o bin/app ./cmd/app

task install:
    @desc "Install dependencies"
    @pre echo "Installing dependencies..."
    go mod download

task test: [build]
    @desc "Run the test suite"
    go test -v ./...

task clean:
    @desc "Remove build artifacts"
    @pre echo "Cleaning..."
    rm -rf bin/

# Docker namespace via import or inline
@group docker
task docker-build: [build]
    @desc "Build Docker image"
    docker build -t myapp:latest .

@group docker
task docker-push:
    @desc "Push to registry"
    docker push myapp:latest
```

## CLI Comparison

| Mage                  | Jake                     |
| --------------------- | ------------------------ |
| `mage`                | `jake`                   |
| `mage build`          | `jake build`             |
| `mage -l`             | `jake --list`            |
| `mage -v build`       | `jake -v build`          |
| `mage docker:build`   | `jake docker-build`      |
| `mage -compile ./bin` | Not needed (interpreted) |

## Key Differences

| Feature         | Mage               | Jake                  |
| --------------- | ------------------ | --------------------- |
| **Language**    | Go                 | DSL                   |
| **Compilation** | Required first run | None (interpreted)    |
| **File deps**   | Manual             | Native `file` recipes |
| **Parallel**    | Manual goroutines  | `-j` flag             |
| **Namespaces**  | `mg.Namespace`     | `@import as`          |

## What You Gain

1. **No compilation** - Runs immediately
2. **File dependency tracking** - Built-in `file` recipes
3. **Simpler syntax** - No Go boilerplate
4. **Parallel execution** - Built-in with `-j`
5. **Watch mode** - `jake -w build`

## What You Lose

1. **Go type safety** - No compile-time checks
2. **Go ecosystem** - Can't import Go packages
3. **Complex logic** - Move to external scripts

## See Also

- [File Targets](/docs/file-targets/) - Dependency tracking
- [Imports](/docs/imports/) - Namespacing with imports
- [Parallel Execution](/examples/parallel-execution/)
