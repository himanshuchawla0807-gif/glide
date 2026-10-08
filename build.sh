#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
OUTPUT_DIR="$SOURCE_DIR/dist"
mkdir -p "$OUTPUT_DIR"
APP="$OUTPUT_DIR/Glide.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SOURCE_DIR/.build"
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  "$SOURCE_DIR"/Sources/*.swift -o "$APP/Contents/MacOS/Glide" \
  -framework SwiftUI -framework AppKit -framework Carbon -framework ServiceManagement
xcrun swiftc -O -target "$(uname -m)-apple-macosx14.0" "$SOURCE_DIR/NativeHost/main.swift" "$SOURCE_DIR/Sources/BridgeProtocol.swift" -o "$APP/Contents/MacOS/GlideBridge"
ditto "$SOURCE_DIR/Companion" "$APP/Contents/Resources/Glide Companion"
# The host is a stdio tool with no Dock presence.
cp "$SOURCE_DIR/Info.plist" "$APP/Contents/Info.plist"
xcrun swift "$SOURCE_DIR/Icon.swift" "$SOURCE_DIR/.build/Glide.iconset"
iconutil -c icns "$SOURCE_DIR/.build/Glide.iconset" -o "$APP/Contents/Resources/Glide.icns"
codesign --force --sign - "$APP/Contents/MacOS/GlideBridge"
codesign --force --sign - "$APP"
echo "Built: $APP"
