#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
APP="${PWD}/dist/轻截.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
  Sources/Document.swift Sources/Canvas.swift Sources/Capture.swift Sources/Views.swift \
  Sources/Shortcuts.swift Sources/App.swift Tests/SelfTest.swift Sources/main.swift \
  -framework AppKit -framework SwiftUI -framework Vision -framework ScreenCaptureKit -framework Carbon \
  -o "$APP/Contents/MacOS/LightShot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - --identifier local.zwkere.lightshot "$APP"
printf '已生成应用：%s\n' "$APP"
