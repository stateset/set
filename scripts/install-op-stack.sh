#!/bin/bash
# Set Chain - OP Stack Installation Script
# Installs op-deployer, op-node, op-geth, op-batcher, op-proposer, op-challenger

set -e

echo "=== Set Chain OP Stack Installation ==="
echo ""

# Configuration
INSTALL_DIR="${INSTALL_DIR:-$HOME/bin}"
OPTIMISM_VERSION="${OPTIMISM_VERSION:-v1.9.4}"
OP_GETH_VERSION="${OP_GETH_VERSION:-v1.101411.2}"
TEMP_DIR=$(mktemp -d)

# Ensure install directory exists
mkdir -p "$INSTALL_DIR"

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    command -v git >/dev/null 2>&1 || { echo "git is required but not installed."; exit 1; }
    command -v go >/dev/null 2>&1 || { echo "go is required but not installed. Install Go 1.21+"; exit 1; }
    command -v make >/dev/null 2>&1 || { echo "make is required but not installed."; exit 1; }

    GO_VERSION=$(go version | grep -oP '\d+\.\d+' | head -1)
    echo "Go version: $GO_VERSION"

    echo "Prerequisites OK"
    echo ""
}

# Install op-deployer from releases
install_op_deployer() {
    echo "Installing op-deployer..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    DEPLOYER_URL="https://github.com/ethereum-optimism/optimism/releases/download/${OPTIMISM_VERSION}/op-deployer_${OPTIMISM_VERSION}_${OS}_${ARCH}.tar.gz"

    echo "Downloading from: $DEPLOYER_URL"
    curl -L "$DEPLOYER_URL" -o "$TEMP_DIR/op-deployer.tar.gz"
    tar -xzf "$TEMP_DIR/op-deployer.tar.gz" -C "$TEMP_DIR"
    cp "$TEMP_DIR/op-deployer" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/op-deployer"

    echo "op-deployer installed to $INSTALL_DIR/op-deployer"
}

# Install op-node from releases
install_op_node() {
    echo "Installing op-node..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    NODE_URL="https://github.com/ethereum-optimism/optimism/releases/download/${OPTIMISM_VERSION}/op-node_${OPTIMISM_VERSION}_${OS}_${ARCH}.tar.gz"

    echo "Downloading from: $NODE_URL"
    curl -L "$NODE_URL" -o "$TEMP_DIR/op-node.tar.gz"
    tar -xzf "$TEMP_DIR/op-node.tar.gz" -C "$TEMP_DIR"
    cp "$TEMP_DIR/op-node" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/op-node"

    echo "op-node installed to $INSTALL_DIR/op-node"
}

# Install op-batcher from releases
install_op_batcher() {
    echo "Installing op-batcher..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    BATCHER_URL="https://github.com/ethereum-optimism/optimism/releases/download/${OPTIMISM_VERSION}/op-batcher_${OPTIMISM_VERSION}_${OS}_${ARCH}.tar.gz"

    echo "Downloading from: $BATCHER_URL"
    curl -L "$BATCHER_URL" -o "$TEMP_DIR/op-batcher.tar.gz"
    tar -xzf "$TEMP_DIR/op-batcher.tar.gz" -C "$TEMP_DIR"
    cp "$TEMP_DIR/op-batcher" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/op-batcher"

    echo "op-batcher installed to $INSTALL_DIR/op-batcher"
}

# Install op-proposer from releases
install_op_proposer() {
    echo "Installing op-proposer..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    PROPOSER_URL="https://github.com/ethereum-optimism/optimism/releases/download/${OPTIMISM_VERSION}/op-proposer_${OPTIMISM_VERSION}_${OS}_${ARCH}.tar.gz"

    echo "Downloading from: $PROPOSER_URL"
    curl -L "$PROPOSER_URL" -o "$TEMP_DIR/op-proposer.tar.gz"
    tar -xzf "$TEMP_DIR/op-proposer.tar.gz" -C "$TEMP_DIR"
    cp "$TEMP_DIR/op-proposer" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/op-proposer"

    echo "op-proposer installed to $INSTALL_DIR/op-proposer"
}

# Install op-challenger from releases
install_op_challenger() {
    echo "Installing op-challenger..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    CHALLENGER_URL="https://github.com/ethereum-optimism/optimism/releases/download/${OPTIMISM_VERSION}/op-challenger_${OPTIMISM_VERSION}_${OS}_${ARCH}.tar.gz"

    echo "Downloading from: $CHALLENGER_URL"
    curl -L "$CHALLENGER_URL" -o "$TEMP_DIR/op-challenger.tar.gz" || echo "op-challenger not available in this release"

    if [ -f "$TEMP_DIR/op-challenger.tar.gz" ]; then
        tar -xzf "$TEMP_DIR/op-challenger.tar.gz" -C "$TEMP_DIR"
        cp "$TEMP_DIR/op-challenger" "$INSTALL_DIR/" 2>/dev/null || true
        chmod +x "$INSTALL_DIR/op-challenger" 2>/dev/null || true
        echo "op-challenger installed to $INSTALL_DIR/op-challenger"
    else
        echo "op-challenger skipped (not available)"
    fi
}

# Install op-geth
install_op_geth() {
    echo "Installing op-geth..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    GETH_URL="https://github.com/ethereum-optimism/op-geth/releases/download/${OP_GETH_VERSION}/geth_${OS}_${ARCH}.tar.gz"

    echo "Downloading from: $GETH_URL"
    curl -L "$GETH_URL" -o "$TEMP_DIR/op-geth.tar.gz"
    tar -xzf "$TEMP_DIR/op-geth.tar.gz" -C "$TEMP_DIR"
    cp "$TEMP_DIR/geth" "$INSTALL_DIR/op-geth"
    chmod +x "$INSTALL_DIR/op-geth"

    echo "op-geth installed to $INSTALL_DIR/op-geth"
}

# Verify installations
verify_installations() {
    echo ""
    echo "=== Verifying Installations ==="

    for binary in op-deployer op-node op-batcher op-proposer op-geth; do
        if [ -x "$INSTALL_DIR/$binary" ]; then
            echo "  $binary: OK"
        else
            echo "  $binary: MISSING"
        fi
    done

    # Optional challenger
    if [ -x "$INSTALL_DIR/op-challenger" ]; then
        echo "  op-challenger: OK"
    else
        echo "  op-challenger: OPTIONAL (not installed)"
    fi
}

# Print path instructions
print_instructions() {
    echo ""
    echo "=== Installation Complete ==="
    echo ""
    echo "Add the following to your shell profile (~/.bashrc or ~/.zshrc):"
    echo ""
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
    echo "Then run: source ~/.bashrc (or ~/.zshrc)"
    echo ""
    echo "To verify, run: op-deployer --version"
    echo ""
}

# Cleanup
cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# Main installation
main() {
    check_prerequisites

    echo "Installing OP Stack components to: $INSTALL_DIR"
    echo "Optimism version: $OPTIMISM_VERSION"
    echo "op-geth version: $OP_GETH_VERSION"
    echo ""

    install_op_deployer
    echo ""

    install_op_node
    echo ""

    install_op_batcher
    echo ""

    install_op_proposer
    echo ""

    install_op_challenger
    echo ""

    install_op_geth
    echo ""

    verify_installations
    print_instructions
}

main "$@"
