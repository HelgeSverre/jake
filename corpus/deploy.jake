# Deploy module - imported with "deploy" prefix

env = "staging"

task staging:
    echo "Deploying to {{env}}..."

task production:
    echo "Deploying to production..."

task rollback:
    echo "Rolling back deployment..."
