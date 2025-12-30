---
title: Database Tasks
description: Migrations, seeding, backups, and database management with Jake.
---

A complete workflow for database management including migrations, seeding, backups, and performance analysis.

## Complete Jakefile

```jake
# Database & Backend Jakefile
# ===========================

@dotenv
@require DATABASE_URL

# === Migrations ===

@group db
task migrate:
    @description "Run pending migrations"
    @needs npx
    @pre echo "Running migrations..."
    npx prisma migrate deploy
    @post echo "Migrations complete"

@group db
task migrate-create name:
    @description "Create a new migration"
    @needs npx
    npx prisma migrate dev --name {{name}}
    echo "Created migration: {{name}}"

@group db
task migrate-reset:
    @description "Reset database and run all migrations"
    @confirm "This will DELETE all data. Continue?"
    @needs npx
    npx prisma migrate reset --force
    @post echo "Database reset complete"

@group db
task migrate-status:
    @description "Show migration status"
    @needs npx
    npx prisma migrate status

# === Seeding ===

@group db
task seed:
    @description "Seed database with sample data"
    @needs npx
    @pre echo "Seeding database..."
    npx prisma db seed
    @post echo "Database seeded"

@group db
task seed-prod:
    @description "Seed production essentials only"
    @confirm "Seed production database?"
    @needs npx
    NODE_ENV=production npx prisma db seed -- --production
    echo "Production seed complete"

# === Backups ===

@group backup
task backup:
    @description "Create database backup"
    @needs pg_dump
    backup_file="backups/db-$(date +%Y%m%d-%H%M%S).sql"
    mkdir -p backups
    pg_dump $DATABASE_URL > $backup_file
    gzip $backup_file
    @post echo "Backup created: ${backup_file}.gz"

@group backup
task backup-list:
    @description "List available backups"
    @quiet
    ls -lah backups/*.sql.gz 2>/dev/null || echo "No backups found"

@group backup
task restore file:
    @description "Restore from backup file"
    @confirm "Restore from {{file}}? This will overwrite current data."
    @needs psql gunzip
    gunzip -c {{file}} | psql $DATABASE_URL
    @post echo "Database restored from {{file}}"

@group backup
task backup-s3:
    @description "Backup to S3"
    @require AWS_BUCKET
    @needs aws pg_dump
    backup_file="db-$(date +%Y%m%d-%H%M%S).sql.gz"
    pg_dump $DATABASE_URL | gzip | aws s3 cp - s3://$AWS_BUCKET/backups/$backup_file
    @post echo "Backup uploaded to s3://$AWS_BUCKET/backups/$backup_file"

# === Schema ===

@group schema
task schema-push:
    @description "Push schema changes (dev only)"
    @needs npx
    npx prisma db push
    echo "Schema pushed"

@group schema
task schema-pull:
    @description "Pull schema from database"
    @needs npx
    npx prisma db pull
    echo "Schema pulled"

@group schema
task schema-generate:
    @description "Generate Prisma client"
    @needs npx
    npx prisma generate
    echo "Client generated"

@group schema
task schema-studio:
    @description "Open Prisma Studio"
    @needs npx
    npx prisma studio

# === Performance ===

@group perf
task analyze-queries:
    @description "Analyze slow queries"
    @needs psql
    psql $DATABASE_URL -c "SELECT query, calls, mean_time, total_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

@group perf
task vacuum:
    @description "Run VACUUM ANALYZE"
    @needs psql
    @pre echo "Running VACUUM ANALYZE..."
    psql $DATABASE_URL -c "VACUUM ANALYZE;"
    @post echo "Vacuum complete"

@group perf
task table-sizes:
    @description "Show table sizes"
    @needs psql
    psql $DATABASE_URL -c "SELECT relname AS table, pg_size_pretty(pg_total_relation_size(relid)) AS size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;"

# === Setup ===

@default
task setup: [schema-generate, migrate, seed]
    @description "Full database setup"
    echo "Database setup complete!"

task reset: [migrate-reset, seed]
    @description "Reset and reseed database"
    echo "Database reset complete!"

# === Utilities ===

task shell:
    @description "Open database shell"
    @needs psql
    psql $DATABASE_URL

task exec query:
    @description "Execute SQL query"
    @needs psql
    psql $DATABASE_URL -c "{{query}}"
```

## Usage

```bash
jake setup                          # Full database setup
jake migrate                        # Run migrations
jake migrate-create add-users       # Create new migration
jake seed                           # Seed data
jake backup                         # Create backup
jake restore file=backups/db.sql.gz # Restore backup
jake shell                          # Open psql
```

## Key Features

### Migration Workflow

Complete migration lifecycle:

```bash
jake migrate-status      # Check current state
jake migrate-create add-users  # Create migration
jake migrate             # Apply migrations
jake migrate-reset       # Start fresh (destructive)
```

### Automated Backups

Local and cloud backups:

```jake
task backup:
    backup_file="backups/db-$(date +%Y%m%d-%H%M%S).sql"
    pg_dump $DATABASE_URL > $backup_file
    gzip $backup_file

task backup-s3:
    pg_dump $DATABASE_URL | gzip | aws s3 cp - s3://$AWS_BUCKET/backups/$backup_file
```

### Safe Destructive Operations

Confirmations prevent accidents:

```jake
task migrate-reset:
    @confirm "This will DELETE all data. Continue?"
    npx prisma migrate reset --force
```

### Performance Analysis

Built-in performance tools:

```bash
jake analyze-queries  # Show slow queries
jake vacuum           # Run VACUUM ANALYZE
jake table-sizes      # Show table sizes
```

## Customization

### For MySQL

Adjust commands for MySQL:

```jake
task backup:
    @needs mysqldump
    backup_file="backups/db-$(date +%Y%m%d-%H%M%S).sql"
    mysqldump -u $DB_USER -p$DB_PASSWORD $DB_NAME > $backup_file
    gzip $backup_file

task shell:
    @needs mysql
    mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME
```

### For Different ORMs

Replace Prisma commands with your ORM:

```jake
# Knex
task migrate:
    npx knex migrate:latest

# Drizzle
task migrate:
    npx drizzle-kit push:pg

# TypeORM
task migrate:
    npx typeorm migration:run
```

## See Also

- [Environment Validation](/examples/environment-validation/) - Secure credential handling
- [Docker Workflows](/examples/docker-workflows/) - Database containers
