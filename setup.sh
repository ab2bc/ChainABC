#!/usr/bin/env bash
set -euo pipefail

# ChainABC Workspace Setup Script
# This script sets up the development environment for ChainABC projects

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err() { echo -e "${RED}[error]${NC} $*"; }
info() { echo -e "${BLUE}[info]${NC} $*"; }

log "ChainABC Workspace Setup"
echo ""

# Check operating system
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="Linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macOS"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
  OS="Windows"
else
  OS="Unknown"
fi

info "Operating System: $OS"
echo ""

# Check for Wine (Linux/macOS)
if [[ "$OS" == "Linux" ]] || [[ "$OS" == "macOS" ]]; then
  log "Checking Wine installation..."
  if command -v wine >/dev/null 2>&1; then
    WINE_VERSION=$(wine --version 2>/dev/null || echo "unknown")
    info "✓ Wine installed: $WINE_VERSION"
  else
    warn "✗ Wine not installed"
    info "Install Wine:"
    if [[ "$OS" == "Linux" ]]; then
      echo "  sudo apt install wine winetricks -y"
    else
      echo "  brew install --cask wine-stable"
    fi
  fi
  
  # Check for winetricks
  if command -v winetricks >/dev/null 2>&1; then
    info "✓ Winetricks installed"
  else
    warn "✗ Winetricks not installed"
    info "Install: sudo apt install winetricks -y"
  fi
  
  # Check for .NET Desktop Runtime in Wine
  if wine dotnet --list-runtimes 2>/dev/null | grep -q "Microsoft.WindowsDesktop.App"; then
    info "✓ .NET Desktop Runtime 8 installed in Wine"
  else
    warn "✗ .NET Desktop Runtime 8 not installed in Wine"
    info "Install: winetricks dotnetdesktop8"
  fi
fi

echo ""
log "Checking project repositories..."

# Check AManager
if [[ -d "AManager/.git" ]]; then
  cd AManager
  AMANAGER_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  AMANAGER_STATUS=$(git status --porcelain 2>/dev/null | wc -l)
  cd ..
  info "✓ AManager repository (branch: $AMANAGER_BRANCH, changes: $AMANAGER_STATUS)"
else
  warn "✗ AManager repository not initialized"
fi

# Check SuiRenamer
if [[ -d "SuiRenamer/.git" ]]; then
  cd SuiRenamer
  SUIRENAMER_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  SUIRENAMER_STATUS=$(git status --porcelain 2>/dev/null | wc -l)
  cd ..
  info "✓ SuiRenamer repository (branch: $SUIRENAMER_BRANCH, changes: $SUIRENAMER_STATUS)"
else
  warn "✗ SuiRenamer repository not initialized"
fi

echo ""
log "Checking build outputs..."

# Check AManager build
if [[ -f "AManager/bin/Release/net8.0-windows7.0/AManager.exe" ]]; then
  info "✓ AManager Release build available"
else
  warn "✗ AManager Release build not found"
fi

if [[ -f "AManager/bin/Debug/net8.0-windows7.0/AManager.exe" ]]; then
  info "✓ AManager Debug build available"
else
  info "  AManager Debug build not found (optional)"
fi

echo ""
log "Setup Summary"
echo ""

if [[ "$OS" == "Linux" ]] || [[ "$OS" == "macOS" ]]; then
  if command -v wine >/dev/null 2>&1 && wine dotnet --list-runtimes 2>/dev/null | grep -q "Microsoft.WindowsDesktop.App"; then
    log "✓ Environment ready for running AManager"
    echo ""
    info "To run AManager:"
    echo "  cd AManager"
    echo "  ./run.sh"
  else
    warn "Environment setup incomplete"
    echo ""
    info "Complete setup steps:"
    if ! command -v wine >/dev/null 2>&1; then
      echo "  1. Install Wine: sudo apt install wine winetricks -y"
    fi
    if ! wine dotnet --list-runtimes 2>/dev/null | grep -q "Microsoft.WindowsDesktop.App"; then
      echo "  2. Install .NET: winetricks dotnetdesktop8"
    fi
    echo "  3. Run: cd AManager && ./run.sh"
  fi
else
  log "✓ Windows environment - can build and run natively"
  echo ""
  info "To build:"
  echo "  cd AManager"
  echo "  dotnet build AManager.csproj -c Release"
  echo ""
  info "To run:"
  echo "  cd AManager/bin/Release/net8.0-windows7.0"
  echo "  ./AManager.exe"
fi

echo ""
log "Setup complete!"
