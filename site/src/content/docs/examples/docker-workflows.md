---
title: Docker Workflows
description: Building, pushing, and managing Docker containers with Jake.
---

A complete workflow for Docker development including building, pushing, docker-compose, and cleanup.

## Complete Jakefile

```jake
# Docker Workflow Jakefile
# ========================

@dotenv
@require DOCKER_REGISTRY

# Configuration
app_name = "myapp"
registry = "${DOCKER_REGISTRY}"
tag = "latest"

# === Building ===

@default
@group docker
@description "Build Docker image"
task build:
    @needs docker
    @pre echo "Building {{app_name}}:{{tag}}..."
    docker build -t {{app_name}}:{{tag}} .
    docker tag {{app_name}}:{{tag}} {{registry}}/{{app_name}}:{{tag}}
    @post echo "Built: {{registry}}/{{app_name}}:{{tag}}"

@group docker
@description "Build without cache"
task build-no-cache:
    @needs docker
    docker build --no-cache -t {{app_name}}:{{tag}} .

@group docker
@description "Build for multiple architectures"
task build-multi-platform:
    @needs docker
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        -t {{registry}}/{{app_name}}:{{tag}} \
        --push \
        .
    echo "Multi-platform image pushed"

# === Registry Operations ===

@group registry
@description "Login to Docker registry"
task login:
    @require DOCKER_USERNAME DOCKER_PASSWORD
    echo $DOCKER_PASSWORD | docker login {{registry}} -u $DOCKER_USERNAME --password-stdin
    echo "Logged in to {{registry}}"

@group registry
@description "Push image to registry"
task push: [build]
    @needs docker
    @confirm "Push {{app_name}}:{{tag}} to {{registry}}?"
    docker push {{registry}}/{{app_name}}:{{tag}}
    @post echo "Pushed: {{registry}}/{{app_name}}:{{tag}}"

@group registry
@description "Pull latest image"
task pull:
    @needs docker
    docker pull {{registry}}/{{app_name}}:{{tag}}

# === Local Development ===

@group dev
@description "Start services with docker-compose"
task up:
    @needs docker-compose
    docker-compose up -d
    @post echo "Services started"

@group dev
@description "Stop services"
task down:
    @needs docker-compose
    docker-compose down
    @post echo "Services stopped"

@group dev
@description "Restart all services"
task restart: [down, up]
    echo "Services restarted"

@group dev
@description "Follow container logs"
task logs:
    @needs docker-compose
    docker-compose logs -f

@group dev
@description "Open shell in app container"
task shell:
    @needs docker
    docker-compose exec app /bin/sh

@group dev
@description "List running containers"
task ps:
    docker-compose ps

# === Database Containers ===

@group db
@description "Start database container only"
task db-start:
    docker-compose up -d db
    @post echo "Database started"

@group db
@description "Stop database container"
task db-stop:
    docker-compose stop db

@group db
@description "Open database CLI"
task db-shell:
    docker-compose exec db psql -U postgres

@group db
@description "Reset database (DESTRUCTIVE)"
task db-reset:
    @confirm "This will DELETE all data. Continue?"
    docker-compose stop db
    docker-compose rm -f db
    docker volume rm $(docker volume ls -q | grep db-data) 2>/dev/null || true
    docker-compose up -d db
    @post echo "Database reset complete"

# === Cleanup ===

@group cleanup
@description "Remove stopped containers"
task clean-containers:
    docker container prune -f
    echo "Removed stopped containers"

@group cleanup
@description "Remove dangling images"
task clean-images:
    docker image prune -f
    echo "Removed dangling images"

@group cleanup
@description "Remove unused volumes"
task clean-volumes:
    @confirm "Remove unused volumes?"
    docker volume prune -f
    echo "Removed unused volumes"

@group cleanup
@description "Full Docker cleanup"
task clean-all: [clean-containers, clean-images]
    @confirm "This will remove all unused Docker resources. Continue?"
    docker system prune -af
    echo "Full cleanup complete"

# === Production ===

@group prod
@description "Build and deploy to production"
task deploy: [build, push]
    @confirm "Deploy to production?"
    @require DEPLOY_HOST
    ssh $DEPLOY_HOST "docker pull {{registry}}/{{app_name}}:{{tag}} && docker-compose up -d"
    @post echo "Deployed to production!"

@group prod
@description "Rollback to previous version"
task rollback:
    @require DEPLOY_HOST PREVIOUS_TAG
    @confirm "Rollback to $PREVIOUS_TAG?"
    ssh $DEPLOY_HOST "docker pull {{registry}}/{{app_name}}:$PREVIOUS_TAG && docker-compose up -d"
    echo "Rolled back to $PREVIOUS_TAG"

# === Utility ===

@description "Show current image version"
task version:
    @quiet
    docker images {{app_name}} --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
```

## Usage

```bash
jake build                      # Build Docker image
jake build tag=v1.2.3           # Build with specific tag
jake up                         # Start docker-compose services
jake logs                       # Follow logs
jake push                       # Push to registry
jake deploy                     # Deploy to production
jake clean-all                  # Full Docker cleanup
```

## Key Features

### Tagged Builds

Override the tag with parameters:

```bash
jake build tag=v1.2.3
jake push tag=v1.2.3
```

### Multi-Platform Builds

Build for multiple architectures with buildx:

```jake
task build-multi-platform:
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        -t {{registry}}/{{app_name}}:{{tag}} \
        --push \
        .
```

### Development Workflow

Quick commands for local development:

```bash
jake up       # Start services
jake logs     # View logs
jake shell    # Enter container
jake restart  # Restart everything
jake down     # Stop services
```

### Safe Destructive Operations

Confirmations for dangerous commands:

```jake
task db-reset:
    @confirm "This will DELETE all data. Continue?"
    # ... reset database
```

## Customization

Update configuration variables:

```jake
app_name = "myapp";
registry = "${DOCKER_REGISTRY}";
tag = "latest";
```

## docker-compose.yml Example

```yaml
version: "3.8"
services:
  app:
    build: .
    ports:
      - "3000:3000"
    depends_on:
      - db
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db:5432/myapp

  db:
    image: postgres:15
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=myapp

volumes:
  db-data:
```

## See Also

- [Environment Validation](/examples/environment-validation/) - `@require` for credentials
- [CI/CD Integration](/examples/cicd-integration/) - Automated Docker builds
