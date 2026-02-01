#!/bin/bash
# Script to build and run Pedef as a proper macOS app bundle

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/debug"
APP_BUNDLE="$BUILD_DIR/Pedef.app"

echo "Building Pedef..."
cd "$PROJECT_DIR"
swift build

echo "Creating app bundle..."
# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/Pedef" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Launching Pedef..."
open "$APP_BUNDLE"

echo "Done!"
