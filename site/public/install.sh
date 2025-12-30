#!/bin/sh
# Jake installer script
# Usage: curl -fsSL jakefile.dev/install.sh | sh
#
# Environment variables:
#   JAKE_VERSION  - Specific version to install (default: latest)
#   JAKE_INSTALL  - Installation directory (default: ~/.local/bin)

set -e

REPO="HelgeSverre/jake"
BINARY_NAME="jake"
DEFAULT_INSTALL_DIR="$HOME/.local/bin"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

info() {
    printf "${BLUE}info${NC}: %s\n" "$1"
}

success() {
    printf "${GREEN}success${NC}: %s\n" "$1"
}

warn() {
    printf "${YELLOW}warning${NC}: %s\n" "$1"
}

error() {
    printf "${RED}error${NC}: %s\n" "$1" >&2
    exit 1
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        FreeBSD*) echo "freebsd" ;;
        *)       error "Unsupported operating system: $(uname -s)" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l)        echo "armv7" ;;
        *)             error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# Get latest version from GitHub
get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

# Download file
download() {
    url="$1"
    output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

# Check if directory is in PATH
check_path() {
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
        *)        return 1 ;;
    esac
}

# Suggest adding to PATH
suggest_path() {
    install_dir="$1"

    if check_path "$install_dir"; then
        return
    fi

    warn "$install_dir is not in your PATH"

    # Detect shell and suggest appropriate config file
    shell_name="$(basename "$SHELL")"
    case "$shell_name" in
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                config_file="$HOME/.bashrc"
            else
                config_file="$HOME/.bash_profile"
            fi
            ;;
        zsh)
            config_file="$HOME/.zshrc"
            ;;
        fish)
            config_file="$HOME/.config/fish/config.fish"
            echo ""
            echo "Add to $config_file:"
            echo "  fish_add_path $install_dir"
            return
            ;;
        *)
            config_file="$HOME/.profile"
            ;;
    esac

    echo ""
    echo "Add to $config_file:"
    echo "  export PATH=\"$install_dir:\$PATH\""
}

main() {
    os=$(detect_os)
    arch=$(detect_arch)

    info "Detected OS: $os, Architecture: $arch"

    # Get version
    if [ -n "$JAKE_VERSION" ]; then
        version="$JAKE_VERSION"
    else
        info "Fetching latest version..."
        version=$(get_latest_version)
        if [ -z "$version" ]; then
            error "Failed to get latest version. Set JAKE_VERSION to install a specific version."
        fi
    fi

    info "Installing jake $version"

    # Binary naming matches release.yml artifacts
    binary_name="jake-${os}-${arch}"
    download_url="https://github.com/${REPO}/releases/download/${version}/${binary_name}"

    # Create temp directory
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    # Download binary
    info "Downloading from $download_url"
    download "$download_url" "$tmp_dir/jake" || error "Failed to download. Check if release exists: https://github.com/${REPO}/releases/tag/${version}"

    # Make executable
    chmod +x "$tmp_dir/jake"

    # Verify it runs
    if ! "$tmp_dir/jake" --version >/dev/null 2>&1; then
        error "Downloaded binary failed to execute. Your platform may not be supported."
    fi

    # Install
    install_dir="${JAKE_INSTALL:-$DEFAULT_INSTALL_DIR}"
    mkdir -p "$install_dir"

    mv "$tmp_dir/jake" "$install_dir/jake"

    success "Installed jake to $install_dir/jake"

    # Show version
    "$install_dir/jake" --version 2>/dev/null || true

    # Check PATH
    suggest_path "$install_dir"

    echo ""
    success "Installation complete!"
}

main "$@"
