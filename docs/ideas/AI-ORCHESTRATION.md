# AI Agent Orchestration in Jake

A comprehensive design document for integrating AI agent orchestration capabilities into Jake.

## Executive Summary

**Vision**: Enable Jake to orchestrate AI coding agents as naturally as it orchestrates shell commands, creating a declarative workflow automation layer for agentic development.

**Why Jake?**
- Already handles task dependencies, parallel execution, and file watching
- Declarative syntax is ideal for defining multi-step AI workflows
- Existing hook system provides natural integration points
- Lightweight CLI tool vs. heavy frameworks

**Current Status**: Experimental prototype in `jake/ai.jake` using bash + Claude Code CLI.

---

## Competitive Landscape

| Tool | Approach | Strengths | Weaknesses |
|------|----------|-----------|------------|
| **GitHub Copilot Coding Agent** | GitHub-native | Deep integration, auto-PR on CI failure | GitHub-only, closed source, limited customization |
| **OpenAI Codex CLI** | CLI auto-fix | Diagnose → patch → test → PR pipeline | OpenAI-only, focused on CI fixing |
| **Claude-Flow** | Multi-agent swarms | Enterprise features, 100+ MCP tools | Complex setup, heavyweight |
| **Cursor Composer** | IDE-integrated | Excellent UX, multi-file edits | IDE-bound, no CLI automation |
| **Aider** | CLI pair programming | Git-aware, works well in terminal | Single model, chat-focused |
| **Cline/Continue** | IDE extensions | Good VS Code integration | IDE-bound |
| **Jake (proposed)** | Task-file orchestration | Declarative, flexible, lightweight | Experimental, needs development |

### Key Differentiators for Jake

1. **Declarative Workflows**: Define AI pipelines in a Jakefile, version-controlled alongside code
2. **Tool Agnostic**: Can orchestrate any CLI-based AI tool (Claude, Codex, local models)
3. **Incremental Adoption**: Start with simple bash+claude, evolve to native directives
4. **Build System Integration**: AI tasks as first-class citizens alongside build tasks

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Jakefile                                   │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │ @agent defs  │  │ @prompt      │  │ task/file recipes        │   │
│  │              │  │ templates    │  │ with AI integration      │   │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘   │
│                                                                      │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
              ▼                  ▼                  ▼
     ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
     │ Claude Code  │   │ GitHub CLI   │   │ Other AI     │
     │ CLI          │   │ (gh)         │   │ Tools        │
     └──────────────┘   └──────────────┘   └──────────────┘
              │                  │                  │
              ▼                  ▼                  ▼
     ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
     │ Code Changes │   │ Issues/PRs   │   │ Artifacts    │
     │ Git Commits  │   │ CI/CD        │   │ Reports      │
     └──────────────┘   └──────────────┘   └──────────────┘
```

### Bidirectional Integration

```
┌─────────────────┐                    ┌─────────────────┐
│                 │  Jake calls AI     │                 │
│      Jake       │ ─────────────────► │   Claude Code   │
│    (Jakefile)   │                    │   (AI Agent)    │
│                 │ ◄───────────────── │                 │
│                 │  AI calls Jake     │                 │
└─────────────────┘  (via MCP/hooks)   └─────────────────┘
```

---

## Proposed Directives

### @agent - Named Agent Configurations

Define reusable AI agent configurations with specific capabilities and constraints.

```jake
@agent coder "claude-code" {
    model: "claude-sonnet-4-20250514"
    perms: "read,edit,git-add,git-commit"
    timeout: 300
    context: "You are a careful coder. Make minimal changes."
}

@agent reviewer "claude-code" {
    model: "claude-sonnet-4-20250514"
    perms: "read"
    context: "You are a code reviewer. Be thorough but concise."
}

@agent fixer "claude-code" {
    model: "claude-sonnet-4-20250514"
    perms: "read,edit,bash"
    context: "You are a CI/CD debugging expert."
}
```

**Implementation**: Shell out to `claude -p "..." --model X --allowedTools Y`

### @prompt - Reusable Prompt Templates

Define prompt templates with variable interpolation.

```jake
@prompt validate-docs:
    """
    Review README.md, CHANGELOG.md, TODO.md for accuracy.
    Output JSON: { "status": "ok" | "needs-update", "issues": [...] }
    """

@prompt fix-issue issue:
    """
    Fix GitHub issue #{{issue}}.
    1. Read the issue description
    2. Understand the problem
    3. Make minimal changes to fix it
    4. Add tests if appropriate
    """
```

**Usage**:
```jake
task validate:
    @in reviewer
    @prompt validate-docs
```

### @in - Execution Context Switch

Switch execution context between local, remote (SSH), containers, and AI agents.

```jake
task deploy:
    # Local build
    npm run build

    # AI updates changelog
    @in coder
    Update CHANGELOG.md with recent changes

    # Deploy to remote server
    @in ssh://deploy@prod.example.com
    cd /var/www && git pull
    systemctl restart app

    # AI validates deployment
    @in reviewer
    Verify the deployment was successful
```

**Context Types**:
- `@in agent-name` - Execute via AI agent
- `@in ssh://user@host` - Execute via SSH
- `@in docker://image` - Execute in container
- `@in sudo` - Execute as root

### @retry - Retry with Backoff

Automatic retry with configurable strategies.

```jake
task flaky-test:
    @retry 3 backoff=exponential on_fail="jake ai.investigate"
    npm test
```

**Options**:
- `N` - Maximum attempts
- `backoff=linear|exponential|fixed` - Backoff strategy
- `delay=N` - Base delay in seconds
- `on_fail="command"` - Command to run between retries

### @await - Wait for Async Operations

Wait for external operations to complete.

```jake
task release:
    gh release create v1.0
    @await github-action "release.yml" timeout=600
    @on_error jake ai.fix-ci
```

**Supported Waiters**:
- `github-action "workflow"` - Wait for GitHub Actions workflow
- `http "url"` - Wait for HTTP endpoint to return 200
- `file "path"` - Wait for file to exist
- `command "cmd"` - Wait for command to succeed

---

## Use Cases

### 1. Release Automation

Full workflow from code to production with AI validation at each step.

```jake
task release version:
    @confirm "Release v{{version}}?"

    # AI validates docs are accurate
    @in reviewer
    @prompt validate-docs
    @expect status="ok" else fail "Docs need updating"

    # AI generates changelog
    @in coder
    @prompt changelog-entry version={{version}}

    # Standard release steps
    git add CHANGELOG.md
    git commit -m "docs: release v{{version}}"
    git tag v{{version}}
    git push --tags

    # Create release and wait for CI
    gh release create v{{version}}
    @await github-action "release.yml" timeout=600
    @on_error jake ai.fix-ci
```

### 2. CI Failure Auto-Fix

Agent fetches logs, investigates, proposes fix, optionally auto-commits.

```jake
@on_error ci
task fix-ci:
    @in fixer
    """
    The CI failed. Here are the logs:
    $(gh run view --log-failed | head -500)

    1. Identify the root cause
    2. Make the minimal fix
    3. Commit with message "fix: <description>"
    """

    # Retry CI
    git push
    @await github-action "ci.yml"
```

### 3. Documentation Sync

Agent validates docs match code, updates changelog, keeps README current.

```jake
@after git.commit
task sync-docs:
    @in reviewer
    """
    Check if this commit requires documentation updates.
    Review: README.md, CHANGELOG.md, docs/
    If updates needed, list them.
    """
```

### 4. Code Review

Agent reviews PRs, flags issues, suggests improvements.

```jake
task review-pr pr:
    @in reviewer
    """
    Review PR #{{pr}}:
    $(gh pr diff {{pr}})

    Check for:
    - Bugs and logic errors
    - Security vulnerabilities
    - Performance issues
    - Code style violations
    - Missing tests
    - Documentation needs

    Provide actionable feedback.
    """
```

### 5. Dependency Updates

Agent checks for updates, creates PRs, monitors CI for breakage.

```jake
task update-deps:
    # Check for updates
    @in coder
    """
    Check for dependency updates in:
    - build.zig.zon (Zig dependencies)
    - package.json (if exists)

    For each outdated dependency:
    1. Update to latest compatible version
    2. Run tests to verify
    3. Create a commit
    """

    # Push and monitor
    git push origin update-deps
    gh pr create --title "chore: update dependencies"
    @await github-action "ci.yml"
```

### 6. Test Generation

Agent analyzes code, generates tests, validates coverage.

```jake
task generate-tests file:
    @in coder
    """
    Generate comprehensive tests for {{file}}:
    1. Read and understand the code
    2. Identify edge cases
    3. Write tests that achieve high coverage
    4. Ensure tests are idiomatic for this project
    """

    # Run tests to validate
    zig build test
```

---

## Implementation Roadmap

### Phase 1: Prototype (Current)
- [x] `jake/ai.jake` module with bash + claude CLI
- [x] Prompt templates in `jake/prompts/`
- [x] Basic workflows: validate-docs, changelog, CI investigation
- [ ] Validate patterns work in real usage
- [ ] Document pain points and limitations

### Phase 2: First-Class Prompts
- [ ] Add `@prompt` directive to Jake parser
- [ ] Template variable expansion in multi-line strings
- [ ] `@include "file.md"` for prompt fragments
- [ ] Prompt library/registry concept

### Phase 3: Agent Contexts
- [ ] Add `@agent` definitions to parser
- [ ] Implement `@in <agent>` context switching
- [ ] Shell out to `claude -p "prompt" --flags`
- [ ] Capture and parse agent output
- [ ] Agent output as variables

### Phase 4: Control Flow
- [ ] `@retry` with backoff strategies
- [ ] `@await` for async operations
- [ ] `@expect` for output validation
- [ ] `@on_error` scoped error handlers
- [ ] `@timeout` for AI operations

### Phase 5: Bidirectional Integration
- [ ] MCP server for Jake (let Claude invoke recipes)
- [ ] Generate Claude Code hook configs from Jakefile
- [ ] Session state persistence across recipes
- [ ] Token/cost tracking and budgets

---

## Open Questions

### Permission Model
- How does Jake enforce agent permissions?
- Trust Claude Code's permission system?
- Separate sandbox per agent definition?
- Allow `--dangerously-skip-permissions` equivalent?

### Output Handling
- Capture agent stdout as variable?
- Structured output (JSON) validation?
- Stream to terminal vs. capture?
- Agent return codes?

### Cost/Token Awareness
- Track token usage per agent invocation?
- Budget limits per task/session?
- Warn when approaching limits?
- Cost estimation before execution?

### State Persistence
- Should agents share conversation context?
- Session IDs across recipe invocations?
- Checkpoint/resume for long workflows?
- Memory/RAG integration?

### Parallel Agent Execution
- Run multiple agents concurrently?
- How to handle conflicts?
- Merge strategies for file changes?
- Agent disagreement resolution?

---

## References

### Industry Context
- [The New Stack: AI Coding Tools in 2025 - Welcome to the Agentic CLI Era](https://thenewstack.io/ai-coding-tools-in-2025-welcome-to-the-agentic-cli-era/)
- [AI Engineering Trends 2025: Agents, MCP and Vibe Coding](https://thenewstack.io/ai-engineering-trends-in-2025-agents-mcp-and-vibe-coding/)

### Competitive Tools
- [Elastic: Self-correcting CI pipelines with Claude](https://www.elastic.co/search-labs/blog/ci-pipelines-claude-ai-agent)
- [GitHub Copilot Coding Agent 101](https://github.blog/ai-and-ml/github-copilot/github-copilot-coding-agent-101-getting-started-with-agentic-workflows-on-github/)
- [OpenAI Codex CLI Autofix Guide](https://developers.openai.com/codex/guides/autofix-ci/)
- [GitHub Agent HQ Announcement](https://www.infoworld.com/article/4080888/github-launches-agent-hq-to-bring-order-to-ai-powered-coding.html)

### Claude Code Documentation
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Model Context Protocol](https://modelcontextprotocol.io/)

### Related Projects
- [Claude-Flow](https://github.com/ruvnet/claude-flow) - Multi-agent orchestration
- [Aider](https://aider.chat/) - CLI pair programming
- [zig-clap](https://github.com/Hejsil/zig-clap) - Zig CLI argument parser

---

## Appendix: Current Prototype

The experimental `jake/ai.jake` module provides:

```bash
# Documentation
jake ai.validate-docs       # AI validates doc accuracy
jake ai.suggest-doc-updates # AI suggests updates (read-only)

# Changelog
jake ai.changelog-entry     # Generate changelog from commits
jake ai.update-changelog    # Update CHANGELOG.md

# Release
jake ai.release             # Full AI-assisted release
jake ai.release-dry-run     # Preview release steps

# CI/CD
jake ai.investigate-ci-failure  # Investigate failed runs
jake ai.fix-ci-failure          # Attempt to fix failures
jake ai.watch-ci                # Watch and auto-investigate

# Code Review
jake ai.review-staged       # Review staged changes
jake ai.review-pr           # Review a pull request
jake ai.review-last-commit  # Review last commit

# Utilities
jake ai.ask                 # Quick AI prompt
jake ai.explain             # Explain code/concept
jake ai.test-investigate    # Run tests with AI on failure
```

This prototype validates the patterns before investing in Jake core changes.
