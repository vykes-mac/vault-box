#!/bin/bash
set -e

echo "=== VaultBox Environment Check ==="

# Check Xcode
xcodebuild -version || { echo "ERROR: Xcode not found"; exit 1; }

# Check Swift
swift --version || { echo "ERROR: Swift not found"; exit 1; }

# Resolve SPM dependencies
if [ -d "VaultBox.xcodeproj" ]; then
  echo "=== Resolving SPM dependencies ==="
  xcodebuild -resolvePackageDependencies -project VaultBox.xcodeproj -scheme VaultBox 2>&1 | tail -5
  echo "=== SPM dependencies resolved ==="
fi

# Build check
if [ -d "VaultBox.xcodeproj" ]; then
  echo "=== Building ==="
  xcodebuild build -project VaultBox.xcodeproj -scheme VaultBox \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  echo "=== Build OK ==="
fi

echo "=== Environment Ready ==="
