#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/YamiboReaderIOS.xcodeproj"
SCHEME="YamiboReaderIOS"
BUNDLE_ID="com.arkalin.YamiboReaderIOS"
DERIVED_DATA_PATH="$ROOT_DIR/.derived"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/YamiboReaderIOS.app"

if ! xcrun simctl list devices booted | grep -q "(Booted)"; then
  echo "No booted simulator found. Boot a simulator first."
  exit 1
fi

echo "Building $SCHEME..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH"
  exit 1
fi

echo "Installing app to booted simulator..."
xcrun simctl install booted "$APP_PATH"

echo "Launching app..."
xcrun simctl launch booted "$BUNDLE_ID"
