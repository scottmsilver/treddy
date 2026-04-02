#!/bin/bash
# Run this on the Mac to create the Xcode project.
# Requires: xcodegen (brew install xcodegen) or Xcode.
set -euo pipefail

cd "$(dirname "$0")"

# If xcodegen is available, use it
if command -v xcodegen &>/dev/null; then
    xcodegen generate
    echo "Xcode project generated. Open Treddy.xcodeproj"
    exit 0
fi

# Otherwise install xcodegen and try again
if command -v brew &>/dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
    xcodegen generate
    echo "Xcode project generated. Open Treddy.xcodeproj"
    exit 0
fi

echo "ERROR: Need either xcodegen or Homebrew."
echo "Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
echo "Then: brew install xcodegen && ./create-project.sh"
exit 1
