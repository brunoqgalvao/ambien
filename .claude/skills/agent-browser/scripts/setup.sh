#!/bin/bash
# Setup script for agent-browser skill

set -e

echo "=== Agent-Browser Setup ==="

# Check if already installed
if command -v agent-browser &> /dev/null; then
    echo "✓ agent-browser is already installed"
    agent-browser --version
else
    echo "Installing agent-browser..."
    npm install -g agent-browser
    echo "✓ Installed agent-browser"
fi

# Check if browser is installed
echo ""
echo "Checking browser installation..."
if agent-browser open about:blank 2>/dev/null && agent-browser close 2>/dev/null; then
    echo "✓ Browser is ready"
else
    echo "Installing browser (Chromium)..."
    agent-browser install
    echo "✓ Browser installed"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Quick test:"
echo "  agent-browser open https://example.com"
echo "  agent-browser snapshot"
echo "  agent-browser close"
