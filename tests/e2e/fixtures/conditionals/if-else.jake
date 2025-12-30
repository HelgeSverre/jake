env = "production"

task deploy:
    @if eq({{env}}, "production")
        echo "Deploying to PRODUCTION"
    @elif eq({{env}}, "staging")
        echo "Deploying to STAGING"
    @else
        echo "Unknown environment"
    @end
