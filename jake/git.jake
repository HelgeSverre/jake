# Git & Release Workflow tasks

version = "0.3.0"

@group git
@desc "Show changelog since last tag"
task changelog:
    @pre echo "Changes since last release:"
    git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~10)..HEAD

@group git
@desc "Create and push a git tag for current version"
task tag:
    @confirm Create tag v{{version}} and push to remote?
    git tag -a v{{version}} -m "Release v{{version}}"
    git push origin v{{version}}
    echo "Tagged and pushed v{{version}}"

@group git
@desc "Show project contributors"
task contributors:
    @pre echo "Project contributors:"
    git shortlog -sn
