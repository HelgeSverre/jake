---
title: Migrating from Taskfile
description: Convert your Taskfile.yml to a Jakefile.
tableOfContents:
  minHeadingLevel: 2
  maxHeadingLevel: 2
---

Taskfile (taskfile.dev) is a popular YAML-based task runner. Jake provides similar features with a more concise syntax.

## Syntax Comparison

| Taskfile | Jake |
|----------|------|
| `version: '3'` | Not needed |
| `tasks:` block | Top-level recipes |
| `desc:` | `@desc` or doc comment |
| `cmds:` array | Indented commands |
| `deps:` | `[dependencies]` |
| `vars:` | Variable assignments |
| `dotenv:` | `@dotenv` |
| `sources:`/`generates:` | File recipe |
| `includes:` | `@import` |
| `preconditions:` | `@needs`, `@require` |
| `prompt:` | `@confirm` |

## Basic Task Conversion

### Taskfile

```yaml
version: '3'

tasks:
  build:
    desc: Build the application
    cmds:
      - go build -o app
      - echo "Done"
```

### Jake

```jake
# Build the application
task build:
    go build -o app
    echo "Done"
```

## Variables

### Taskfile

```yaml
version: '3'

vars:
  APP_NAME: myapp
  VERSION:
    sh: git describe --tags

tasks:
  show:
    cmds:
      - echo "{{.APP_NAME}} v{{.VERSION}}"
```

### Jake

```jake
app_name = "myapp"
version = `git describe --tags`

task show:
    echo "{{app_name}} v{{version}}"
```

## Dependencies

### Taskfile

```yaml
tasks:
  build:
    deps: [clean, install]
    cmds:
      - go build -o app

  clean:
    cmds:
      - rm -rf dist/

  install:
    cmds:
      - go mod download
```

### Jake

```jake
task build: [clean, install]
    go build -o app

task clean:
    rm -rf dist/

task install:
    go mod download
```

## File Tracking (sources/generates)

### Taskfile

```yaml
tasks:
  bundle:
    desc: Bundle JavaScript files
    sources:
      - src/**/*.js
      - package.json
    generates:
      - dist/bundle.js
    cmds:
      - esbuild src/index.js --bundle --outfile=dist/bundle.js
```

### Jake

```jake
# Bundle JavaScript files
file dist/bundle.js: src/**/*.js package.json
    esbuild src/index.js --bundle --outfile=dist/bundle.js
```

Jake uses checksum-based tracking like Taskfile, but with a cleaner syntax.

## Environment Variables

### Taskfile

```yaml
version: '3'

dotenv: ['.env', '.env.local']

env:
  DEBUG: true

tasks:
  serve:
    env:
      PORT: 8080
    cmds:
      - ./server
```

### Jake

```jake
@dotenv
@dotenv ".env.local"
@export DEBUG=true

task serve:
    PORT=8080 ./server
```

## Includes / Imports

### Taskfile

```yaml
version: '3'

includes:
  docker:
    taskfile: ./tasks/Docker.yml
    dir: ./docker
    vars:
      IMAGE: myapp

tasks:
  build:
    cmds:
      - task: docker:build
```

### Jake

```jake
@import "tasks/docker.jake" as docker

task build: [docker.build]
    echo "Build complete"
```

## Preconditions

### Taskfile

```yaml
tasks:
  deploy:
    preconditions:
      - sh: test -f .env
        msg: ".env file required"
      - sh: command -v kubectl
        msg: "kubectl not installed"
    cmds:
      - kubectl apply -f deploy.yaml
```

### Jake

```jake
@needs kubectl
task deploy:
    @if not exists(.env)
        echo ".env file required"
        exit 1
    @end
    kubectl apply -f deploy.yaml
```

Or more concisely with `@require` for environment checks:

```jake
@require KUBECONFIG
@needs kubectl

task deploy:
    kubectl apply -f deploy.yaml
```

## Confirmation Prompts

### Taskfile

```yaml
tasks:
  deploy:
    prompt: Deploy to production?
    cmds:
      - ./deploy.sh
```

### Jake

```jake
task deploy:
    @confirm "Deploy to production?"
    ./deploy.sh
```

## For Loops

### Taskfile

```yaml
tasks:
  build-images:
    vars:
      IMAGES: nginx postgres redis
    cmds:
      - for: { var: IMAGES, split: ' ' }
        cmd: docker build -t {{.ITEM}} .
```

### Jake

```jake
task build-images:
    @each nginx postgres redis
        docker build -t {{item}} .
    @end
```

## Deferred Commands (Cleanup)

### Taskfile

```yaml
tasks:
  test:
    cmds:
      - docker-compose up -d
      - defer: docker-compose down
      - go test ./...
```

### Jake

```jake
task test:
    @pre docker-compose up -d
    go test ./...
    @post docker-compose down
```

Post-hooks run even if the recipe fails.

## Platform-Specific Tasks

### Taskfile

```yaml
tasks:
  install:
    platforms: [linux, darwin]
    cmds:
      - make install

  install-windows:
    platforms: [windows]
    cmds:
      - choco install myapp
```

### Jake

```jake
@platform linux macos
task install:
    make install

@platform windows
task install:
    choco install myapp
```

## Complete Migration Example

### Before (Taskfile.yml)

```yaml
version: '3'

dotenv: ['.env']

vars:
  APP_NAME: myapp
  BUILD_DIR: dist

tasks:
  default:
    deps: [build]

  build:
    desc: Build the application
    deps: [clean, install]
    sources:
      - src/**/*.go
      - go.mod
    generates:
      - '{{.BUILD_DIR}}/{{.APP_NAME}}'
    cmds:
      - mkdir -p {{.BUILD_DIR}}
      - go build -o {{.BUILD_DIR}}/{{.APP_NAME}}

  install:
    desc: Install dependencies
    cmds:
      - go mod download
    sources:
      - go.mod
      - go.sum

  clean:
    desc: Remove build artifacts
    cmds:
      - rm -rf {{.BUILD_DIR}}

  test:
    desc: Run tests
    deps: [build]
    cmds:
      - go test ./... -v

  deploy:
    desc: Deploy to server
    deps: [test]
    prompt: "Deploy to production?"
    cmds:
      - rsync -avz {{.BUILD_DIR}}/ server:/app/
```

### After (Jakefile)

```jake
@dotenv

app_name = "myapp"
build_dir = "dist"

@default
task build: [clean, install, dist/{{app_name}}]
    @desc "Build the application"

file dist/{{app_name}}: src/**/*.go go.mod
    mkdir -p {{build_dir}}
    go build -o {{build_dir}}/{{app_name}}

task install:
    @desc "Install dependencies"
    @cache go.mod go.sum
    go mod download

task clean:
    @desc "Remove build artifacts"
    rm -rf {{build_dir}}

task test: [build]
    @desc "Run tests"
    go test ./... -v

task deploy: [test]
    @desc "Deploy to server"
    @confirm "Deploy to production?"
    rsync -avz {{build_dir}}/ server:/app/
```

## CLI Comparison

| Taskfile | Jake |
|----------|------|
| `task` | `jake` |
| `task build` | `jake build` |
| `task --list` | `jake --list` |
| `task --dry` | `jake -n` |
| `task --watch` | `jake -w` |
| `task --parallel t1 t2` | `jake -j t1 t2` |
| `task --force` | Delete cache, re-run |
| `task VAR=value` | `jake var=value` |

## Key Differences

1. **Syntax**: Jake uses a Makefile-inspired DSL instead of YAML
2. **File recipes**: Jake has dedicated `file` keyword vs `sources/generates`
3. **Simpler structure**: No version declaration or nesting required
4. **Single binary**: Both are single binaries, but Jake is smaller (Zig vs Go)

## What You Keep

- Checksum-based file tracking
- Parallel execution
- Includes with namespacing
- Environment variable support
- Watch mode
- Cross-platform support

## See Also

- [Migrating from Make](/guides/migrating-from-make/) - For Make users
- [File Targets](/docs/file-targets/) - Jake's file recipes
- [Imports](/docs/imports/) - Organizing with imports
