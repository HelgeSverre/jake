#!/usr/bin/env bash
#
# sync.sh - Synchronize editor plugin files from canonical sources
#
# This script ensures all editor plugins stay in sync with their canonical
# source files. Run this after making changes to:
#   - editors/vscode-jake/syntaxes/jake.tmLanguage.json (TextMate grammar)
#   - editors/tree-sitter-jake/queries-src/*.scm (tree-sitter queries)
#
# Usage:
#   ./editors/sync.sh           # Sync all plugins
#   ./editors/sync.sh --check   # Check if files are in sync (CI mode)
#   ./editors/sync.sh --help    # Show this help
#
# Canonical Sources:
#   TextMate Grammar:  editors/vscode-jake/syntaxes/jake.tmLanguage.json
#                      → sublime-jake, shiki-jake (direct copy)
#                      → intellij-jake (copied at build time via Gradle)
#
#   Tree-sitter:       editors/tree-sitter-jake/queries-src/*.scm
#                      → queries/jake/*.scm (via build-flavored-queries.py)
#                      → queries-flavored/zed/*.scm (via build-flavored-queries.py)
#                      → zed-jake/languages/jake/*.scm (copied from queries-flavored/zed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track if any files are out of sync
OUT_OF_SYNC=0
CHECK_MODE=0

usage() {
    head -25 "$0" | tail -22 | sed 's/^# \?//'
    exit 0
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Compare files and sync if needed
sync_file() {
    local src="$1"
    local dst="$2"
    local desc="$3"
    
    if [[ ! -f "$src" ]]; then
        log_error "Source file not found: $src"
        return 1
    fi
    
    if [[ ! -f "$dst" ]]; then
        if [[ $CHECK_MODE -eq 1 ]]; then
            log_error "Destination file missing: $dst"
            OUT_OF_SYNC=1
            return 1
        fi
        log_info "Creating: $dst"
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        log_success "Created $desc"
        return 0
    fi
    
    if diff -q "$src" "$dst" > /dev/null 2>&1; then
        log_success "$desc (in sync)"
    else
        if [[ $CHECK_MODE -eq 1 ]]; then
            log_error "$desc is OUT OF SYNC"
            echo "  Source: $src"
            echo "  Target: $dst"
            OUT_OF_SYNC=1
        else
            log_info "Syncing: $desc"
            cp "$src" "$dst"
            log_success "Synced $desc"
        fi
    fi
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --check)
            CHECK_MODE=1
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $arg"
            usage
            ;;
    esac
done

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo " Jake Editor Plugins - File Synchronization"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

if [[ $CHECK_MODE -eq 1 ]]; then
    log_info "Running in CHECK mode (no files will be modified)"
else
    log_info "Running in SYNC mode"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. Sync TextMate Grammars
# ─────────────────────────────────────────────────────────────────────────────
echo "┌─────────────────────────────────────────────────────────────────────────────┐"
echo "│ TextMate Grammar (VS Code → Sublime, Shiki)                                 │"
echo "└─────────────────────────────────────────────────────────────────────────────┘"

TEXTMATE_SRC="vscode-jake/syntaxes/jake.tmLanguage.json"

sync_file "$TEXTMATE_SRC" "sublime-jake/Jake.tmLanguage.json" \
    "VS Code → Sublime TextMate grammar"

sync_file "$TEXTMATE_SRC" "shiki-jake/jake.tmLanguage.json" \
    "VS Code → Shiki TextMate grammar"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. Build and Sync Tree-sitter Queries
# ─────────────────────────────────────────────────────────────────────────────
echo "┌─────────────────────────────────────────────────────────────────────────────┐"
echo "│ Tree-sitter Queries (queries-src → flavored outputs)                        │"
echo "└─────────────────────────────────────────────────────────────────────────────┘"

if [[ $CHECK_MODE -eq 0 ]]; then
    log_info "Running build-flavored-queries.py..."
    if (cd tree-sitter-jake && python3 build-flavored-queries.py 2>&1); then
        log_success "Generated flavored queries for all editors"
    else
        log_warning "Query generation had issues (check build-flavored-queries.py)"
        log_info "Continuing with existing query files..."
    fi
else
    log_info "Skipping query generation in check mode"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. Sync Zed Extension Queries
# ─────────────────────────────────────────────────────────────────────────────
echo "┌─────────────────────────────────────────────────────────────────────────────┐"
echo "│ Zed Extension (tree-sitter-jake/queries-flavored/zed → zed-jake)            │"
echo "└─────────────────────────────────────────────────────────────────────────────┘"

# Sync all .scm files from the flavored zed queries
for scm_file in tree-sitter-jake/queries-flavored/zed/*.scm; do
    if [[ -f "$scm_file" ]]; then
        filename=$(basename "$scm_file")
        sync_file "$scm_file" "zed-jake/languages/jake/$filename" \
            "tree-sitter → Zed $filename"
    fi
done

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ $OUT_OF_SYNC -eq 1 ]]; then
    log_error "Some files are out of sync! Run './editors/sync.sh' to fix."
    exit 1
else
    if [[ $CHECK_MODE -eq 1 ]]; then
        log_success "All files are in sync!"
    else
        log_success "Synchronization complete!"
    fi
fi
echo ""
