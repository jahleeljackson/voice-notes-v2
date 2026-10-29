#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macosx15.0"
SWIFTC=(swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library)

LOGIC=(
  VoiceNotes/Errors.swift
  VoiceNotes/Settings/KeyCombo.swift
  VoiceNotes/Hotkey/HotkeyStateMachine.swift
  VoiceNotes/Hotkey/HotkeyRouter.swift
  VoiceNotes/Cleanup/CleanupPrompt.swift
  VoiceNotes/Support/LogicChecks.swift
  Scripts/logic-check-main.swift
)

echo "Running logic checks"
"${SWIFTC[@]}" -module-name LogicCheck -o build/logic-check "${LOGIC[@]}"
./build/logic-check

if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  echo "Running xcodebuild test"
  xcodebuild -scheme VoiceNotes -destination 'platform=macOS' -quiet test
  exit 0
fi

echo "xcodebuild is unavailable; building the app with swiftc"
mkdir -p build/VoiceNotes.app/Contents/MacOS build/VoiceNotes.app/Contents/Resources
cp VoiceNotes/Info.plist build/VoiceNotes.app/Contents/Info.plist
cp VoiceNotes/Resources/*.wav build/VoiceNotes.app/Contents/Resources/
SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find VoiceNotes -name '*.swift' | sort)
"${SWIFTC[@]}" \
  -module-name VoiceNotes \
  -o build/VoiceNotes.app/Contents/MacOS/VoiceNotes \
  "${SOURCES[@]}"
codesign --force --sign - \
  --entitlements VoiceNotes/VoiceNotes.entitlements \
  build/VoiceNotes.app
echo "Built build/VoiceNotes.app"
