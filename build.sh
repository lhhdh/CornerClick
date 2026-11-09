#!/bin/sh
set -eu
cd "$(dirname "$0")"

APP="build/CornerClick.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/CornerClick" main.swift
cp Info.plist "$APP/Contents/Info.plist"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "signed: ad-hoc"
fi

echo "built: $(pwd)/$APP"
