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
task build:
    @description "Build Docker image"
    @needs docker
    @pre echo "Building {{app_name}}:{{tag}}..."
    docker build -t {{app_name}}:{{tag}} .
    docker tag {{app_name}}:{{tag}} {{registry}}/{{app_name}}:{{tag}}
    @post echo "Built: {{registry}}/{{app_name}}:{{tag}}"

@group docker
task build-no-cache:
    @description "Build without cache"
    @needs docker
    docker build --no-cache -t {{app_name}}:{{tag}} .

@group docker
task build-multi-platform:
    @description "Build for multiple architectures"
    @needs docker
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        -t {{registry}}/{{app_name}}:{{tag}} \
        --push \
        .
    echo "Multi-platform image pushed"

# === Registry Operations ===

@group registry
task login:
    @description "Login to Docker registry"
    @require DOCKER_USERNAME DOCKER_PASSWORD
    echo $DOCKER_PASSWORD | docker login {{registry}} -u $DOCKER_USERNAME --password-stdin
    echo "Logged in to {{registry}}"

@group registry
task push: [build]
    @description "Push image to registry"
    @needs docker
    @confirm "Push {{app_name}}:{{tag}} to {{registry}}?"
    docker push {{registry}}/{{app_name}}:{{tag}}
    @post echo "Pushed: {{registry}}/{{app_name}}:{{tag}}"

@group registry
task pull:
    @description "Pull latest image"
    @needs docker
    docker pull {{registry}}/{{app_name}}:{{tag}}

# === Local Development ===

@group dev
task up:
    @description "Start services with docker-compose"
    @needs docker-compose
    docker-compose up -d
    @post echo "Services started"

@group dev
task down:
    @description "Stop services"
    @needs docker-compose
    docker-compose down
    @post echo "Services stopped"

@group dev
task restart: [down, up]
    @description "Restart all services"
    echo "Services restarted"

@group dev
task logs:
    @description "Follow container logs"
    @needs docker-compose
    docker-compose logs -f

@group dev
task shell:
    @description "Open shell in app container"
    @needs docker
    docker-compose exec app /bin/sh

@group dev
task ps:
    @description "List running containers"
    docker-compose ps

# === Database Containers ===

@group db
task db-start:
    @description "Start database container only"
    docker-compose up -d db
    @post echo "Database started"

@group db
task db-stop:
    @description "Stop database container"
    docker-compose stop db

@group db
task db-shell:
    @description "Open database CLI"
    docker-compose exec db psql -U postgres

@group db
task db-reset:
    @description "Reset database (DESTRUCTIVE)"
    @confirm "This will DELETE all data. Continue?"
    docker-compose stop db
    docker-compose rm -f db
    docker volume rm $(docker volume ls -q | grep db-data) 2>/dev/null || true
    docker-compose up -d db
    @post echo "Database reset complete"

# === Cleanup ===

@group cleanup
task clean-containers:
    @description "Remove stopped containers"
    docker container prune -f
    echo "Removed stopped containers"

@group cleanup
task clean-images:
    @description "Remove dangling images"
    docker image prune -f
    echo "Removed dangling images"

@group cleanup
task clean-volumes:
    @description "Remove unused volumes"
    @confirm "Remove unused volumes?"
    docker volume prune -f
    echo "Removed unused volumes"

@group cleanup
task clean-all: [clean-containers, clean-images]
    @description "Full Docker cleanup"
    @confirm "This will remove all unused Docker resources. Continue?"
    docker system prune -af
    echo "Full cleanup complete"

# === Production ===

@group prod
task deploy: [build, push]
    @description "Build and deploy to production"
    @confirm "Deploy to production?"
    @require DEPLOY_HOST
    ssh $DEPLOY_HOST "docker pull {{registry}}/{{app_name}}:{{tag}} && docker-compose up -d"
    @post echo "Deployed to production!"

@group prod
task rollback:
    @description "Rollback to previous version"
    @require DEPLOY_HOST PREVIOUS_TAG
    @confirm "Rollback to $PREVIOUS_TAG?"
    ssh $DEPLOY_HOST "docker pull {{registry}}/{{app_name}}:$PREVIOUS_TAG && docker-compose up -d"
    echo "Rolled back to $PREVIOUS_TAG"

# === Utility ===

task version:
    @description "Show current image version"
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
app_name = "myapp"
registry = "${DOCKER_REGISTRY}"
tag = "latest"
```

## docker-compose.yml Example

```yaml
version: '3.8'
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
