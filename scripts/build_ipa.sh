#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
xcodebuild -project ThreadsStudio.xcodeproj -scheme ThreadsStudio -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build-device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
app="build-device/Build/Products/Release-iphoneos/ThreadsStudio.app"
test -f "$app/ThreadsStudio"
lipo -info "$app/ThreadsStudio" | grep arm64
mkdir -p dist/Payload
ditto "$app" dist/Payload/ThreadsStudio.app
( cd dist && ditto -c -k --keepParent Payload ThreadsStudio.ipa && shasum -a 256 ThreadsStudio.ipa > ThreadsStudio.ipa.sha256 )
python3 scripts/verify_ipa.py dist/ThreadsStudio.ipa
echo 'Unsigned device IPA ready: dist/ThreadsStudio.ipa. Sign/install using iLoader.'
