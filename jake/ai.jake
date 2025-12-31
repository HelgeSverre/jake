# ============================================================================
# AI-Assisted Tasks (Experimental)
# ============================================================================
#
# This module demonstrates patterns for integrating AI agents with Jake workflows.
# Uses Claude Code CLI for AI operations.
#
# Requirements:
#   - claude CLI installed and authenticated
#   - gh CLI for GitHub operations
#
# Usage:
#   jake ai.validate-docs          # Validate documentation accuracy
#   jake ai.changelog-entry        # Generate changelog from commits
#   jake ai.release version=0.4.0  # Full AI-assisted release
#   jake ai.investigate-ci-failure # Investigate failed CI runs
#   jake ai.review-staged          # Review staged changes
#
# ============================================================================

# Directory for prompt templates
prompts_dir = "jake/prompts"

# ============================================================================
# AI Helper Tasks (Private)
# ============================================================================

# Run Claude with a prompt file
task _ai-prompt promptfile:
    @quiet
    @needs claude "Install: https://docs.anthropic.com/claude-code"
    cat {{prompts_dir}}/{{promptfile}}.md | claude -p -

# ============================================================================
# Documentation Validation
# ============================================================================

@group ai
@desc "AI validates README, CHANGELOG, TODO against codebase"
task validate-docs:
    @needs claude
    @pre echo "Validating documentation accuracy..."
    cat {{prompts_dir}}/validate-docs.md | claude -p -
    @post echo "Validation complete"

@group ai
@desc "AI suggests documentation updates (read-only)"
task suggest-doc-updates:
    @needs claude
    echo "Reviewing documentation for potential updates..."
    claude -p "Review README.md, CHANGELOG.md, TODO.md. List specific updates needed based on current code. Do not make changes, just report." --allowedTools Read Glob Grep

# ============================================================================
# Changelog Automation
# ============================================================================

@group ai
@desc "AI generates changelog entry from commits (prints to stdout)"
task changelog-entry:
    @needs claude git
    @pre echo "Generating changelog entry from recent commits..."
    echo "Recent commits:"
    git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~20")..HEAD
    echo ""
    echo "--- AI Generated Entry ---"
    git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~20")..HEAD | claude -p "$(cat {{prompts_dir}}/changelog-entry.md)"

@group ai
@desc "AI updates CHANGELOG.md with new entry"
task update-changelog version:
    @needs claude git
    @confirm "Let AI update CHANGELOG.md for v{{version}}?"
    @pre echo "Updating CHANGELOG.md for v{{version}}..."
    claude -p "Update CHANGELOG.md with a new entry for version {{version}}. Use 'Keep a Changelog' format. Summarize changes since the last tag. Read the git log and existing CHANGELOG.md first."
    @post git diff CHANGELOG.md

# ============================================================================
# Release Workflow
# ============================================================================

@group ai
@desc "Full AI-assisted release workflow"
task release version:
    @needs claude gh git
    @confirm "Start AI-assisted release for v{{version}}?"
    @pre echo "Step 1/5: Validating docs..."
    jake ai.validate-docs
    @pre echo "Step 2/5: Updating changelog..."
    jake ai.update-changelog version={{version}}
    @pre echo "Step 3/5: Committing..."
    git add CHANGELOG.md README.md TODO.md
    git commit -m "docs: prepare release v{{version}}" || echo "No changes to commit"
    @pre echo "Step 4/5: Tagging v{{version}}..."
    git tag -a v{{version}} -m "Release v{{version}}"
    git push origin main --tags
    @pre echo "Step 5/5: Creating GitHub release..."
    gh release create v{{version}} --generate-notes
    @post echo "Release v{{version}} complete!"

@group ai
@desc "Dry-run of release workflow (no commits/tags)"
task release-dry-run version:
    @needs claude gh git
    echo "=== Release Dry Run for v{{version}} ==="
    echo ""
    echo "Step 1: Would validate docs"
    jake ai.validate-docs
    echo ""
    echo "Step 2: Would generate changelog entry:"
    jake ai.changelog-entry
    echo ""
    echo "Step 3: Would commit: docs: prepare release v{{version}}"
    echo "Step 4: Would tag: v{{version}}"
    echo "Step 5: Would create GitHub release"
    echo ""
    echo "=== Dry run complete. Run 'jake ai.release version={{version}}' to execute ==="

# ============================================================================
# CI Failure Investigation
# ============================================================================

@group ai
@desc "AI investigates latest failed GitHub Actions run"
task investigate-ci-failure:
    @needs claude gh
    @pre echo "Fetching failed CI logs..."
    gh run list --status=failure --limit 1 --json databaseId -q '.[0].databaseId' > /tmp/jake-failed-run.txt 2>/dev/null || echo "" > /tmp/jake-failed-run.txt
    @if exists(/tmp/jake-failed-run.txt)
        echo "Investigating latest failed run..."
        gh run view $(cat /tmp/jake-failed-run.txt) --log-failed 2>&1 | head -500 | claude -p "$(cat {{prompts_dir}}/investigate-ci.md)"
    @else
        echo "No failed runs found!"
    @end

@group ai
@desc "AI attempts to fix CI failure"
task fix-ci-failure:
    @needs claude gh
    @confirm "Let AI attempt to fix CI failure?"
    @pre echo "Fetching failure logs..."
    gh run view $(gh run list --status=failure --limit 1 --json databaseId -q '.[0].databaseId') --log-failed 2>&1 | head -500 > /tmp/ci-failure.log
    echo "Attempting fix..."
    claude -p "Based on this CI failure log, make the minimal fix needed. Only edit files if you're confident about the fix. Be conservative." < /tmp/ci-failure.log
    @post echo "Review changes with: git diff"

@group ai
@desc "Watch CI and auto-investigate on failure"
task watch-ci workflow="ci.yml":
    @needs gh
    @pre echo "Watching {{workflow}}..."
    gh run watch $(gh run list --workflow={{workflow}} --limit 1 --json databaseId -q '.[0].databaseId') --exit-status || jake ai.investigate-ci-failure

# ============================================================================
# Code Review Automation
# ============================================================================

@group ai
@desc "AI reviews staged changes (read-only)"
task review-staged:
    @needs claude git
    @pre echo "Reviewing staged changes..."
    git diff --cached | claude -p "Review this diff. Check for: bugs, security issues, performance problems, style issues. Be concise and actionable." --allowedTools Read Glob Grep

@group ai
@desc "AI reviews a PR (read-only)"
task review-pr pr:
    @needs claude gh
    @pre echo "Reviewing PR #{{pr}}..."
    gh pr diff {{pr}} | claude -p "Review this PR diff. Summarize the changes, then list any concerns about: bugs, security, performance, style. Be concise." --allowedTools Read Glob Grep

@group ai
@desc "AI reviews last commit (read-only)"
task review-last-commit:
    @needs claude git
    @pre echo "Reviewing last commit..."
    git show --stat HEAD
    echo ""
    git diff HEAD~1..HEAD | claude -p "Review this commit diff. Flag any issues with: bugs, security, performance. Be brief." --allowedTools Read Glob Grep

# ============================================================================
# Quick Actions
# ============================================================================

@group ai
@desc "Quick AI task with custom prompt"
task ask prompt:
    @needs claude
    claude -p "{{prompt}}"

@group ai
@desc "AI explains a file or concept (read-only)"
task explain target:
    @needs claude
    claude -p "Explain {{target}} in this codebase. Be concise." --allowedTools Read Glob Grep
