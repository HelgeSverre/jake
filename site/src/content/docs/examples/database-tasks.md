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
@desc "Run pending migrations"
task migrate:
    @needs npx
    @pre echo "Running migrations..."
    npx prisma migrate deploy
    @post echo "Migrations complete"

@group db
@desc "Create a new migration"
task migrate-create name:
    @needs npx
    npx prisma migrate dev --name {{name}}
    echo "Created migration: {{name}}"

@group db
@desc "Reset database and run all migrations"
task migrate-reset:
    @confirm "This will DELETE all data. Continue?"
    @needs npx
    npx prisma migrate reset --force
    @post echo "Database reset complete"

@group db
@desc "Show migration status"
task migrate-status:
    @needs npx
    npx prisma migrate status

# === Seeding ===

@group db
@desc "Seed database with sample data"
task seed:
    @needs npx
    @pre echo "Seeding database..."
    npx prisma db seed
    @post echo "Database seeded"

@group db
@desc "Seed production essentials only"
task seed-prod:
    @confirm "Seed production database?"
    @needs npx
    NODE_ENV=production npx prisma db seed -- --production
    echo "Production seed complete"

# === Backups ===

@group backup
@desc "Create database backup"
task backup:
    @needs pg_dump
    backup_file="backups/db-$(date +%Y%m%d-%H%M%S).sql"
    mkdir -p backups
    pg_dump $DATABASE_URL > $backup_file
    gzip $backup_file
    @post echo "Backup created: ${backup_file}.gz"

@group backup
@desc "List available backups"
task backup-list:
    @quiet
    ls -lah backups/*.sql.gz 2>/dev/null || echo "No backups found"

@group backup
@desc "Restore from backup file"
@needs psql gunzip
task restore source:
    @confirm "Restore from {{source}}? This will overwrite current data."
    gunzip -c {{source}} | psql $DATABASE_URL
    @post echo "Database restored from {{source}}"

@group backup
@desc "Backup to S3"
task backup-s3:
    @require AWS_BUCKET
    @needs aws pg_dump
    backup_file="db-$(date +%Y%m%d-%H%M%S).sql.gz"
    pg_dump $DATABASE_URL | gzip | aws s3 cp - s3://$AWS_BUCKET/backups/$backup_file
    @post echo "Backup uploaded to s3://$AWS_BUCKET/backups/$backup_file"

# === Schema ===

@group schema
@desc "Push schema changes (dev only)"
task schema-push:
    @needs npx
    npx prisma db push
    echo "Schema pushed"

@group schema
@desc "Pull schema from database"
task schema-pull:
    @needs npx
    npx prisma db pull
    echo "Schema pulled"

@group schema
@desc "Generate Prisma client"
task schema-generate:
    @needs npx
    npx prisma generate
    echo "Client generated"

@group schema
@desc "Open Prisma Studio"
task schema-studio:
    @needs npx
    npx prisma studio

# === Performance ===

@group perf
@desc "Analyze slow queries"
task analyze-queries:
    @needs psql
    psql $DATABASE_URL -c "SELECT query, calls, mean_time, total_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

@group perf
@desc "Run VACUUM ANALYZE"
task vacuum:
    @needs psql
    @pre echo "Running VACUUM ANALYZE..."
    psql $DATABASE_URL -c "VACUUM ANALYZE;"
    @post echo "Vacuum complete"

@group perf
@desc "Show table sizes"
task table-sizes:
    @needs psql
    psql $DATABASE_URL -c "SELECT relname AS table, pg_size_pretty(pg_total_relation_size(relid)) AS size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;"

# === Setup ===

@default
@desc "Full database setup"
task setup: [schema-generate, migrate, seed]
    echo "Database setup complete!"

@desc "Reset and reseed database"
task reset: [migrate-reset, seed]
    echo "Database reset complete!"

# === Utilities ===

@desc "Open database shell"
task shell:
    @needs psql
    psql $DATABASE_URL

@desc "Execute SQL query"
task exec query:
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
