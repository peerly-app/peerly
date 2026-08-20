#!/usr/bin/env bash
set -euo pipefail

REPO="peero-app/peero"

case "$(uname -s)" in
  Darwin)
    echo "macOS detected - installing via Homebrew..."
    brew install --cask peero-app/tap/peero
    ;;
  Linux)
    if [ -f /etc/debian_version ] && command -v apt-get >/dev/null 2>&1; then
      echo "Debian/Ubuntu detected - installing the .deb package..."
      tmp="$(mktemp -d)"
      curl -fsSL -o "$tmp/peero.deb" "https://github.com/${REPO}/releases/latest/download/peero.deb"
      sudo apt-get install -y "$tmp/peero.deb"
      rm -rf "$tmp"
    else
      echo "Linux distribution detected - installing the AppImage..."
      mkdir -p "$HOME/.local/bin"
      curl -fsSL -o "$HOME/.local/bin/peero.AppImage" "https://github.com/${REPO}/releases/latest/download/peero.AppImage"
      chmod +x "$HOME/.local/bin/peero.AppImage"
      echo "Installed to ~/.local/bin/peero.AppImage"
      echo "Make sure ~/.local/bin is on your PATH."
    fi
    ;;
  *)
    echo "This script does not support your platform."
    echo "Windows: download the installer from https://github.com/${REPO}/releases/latest"
    exit 1
    ;;
esac

echo "Peero installed."
