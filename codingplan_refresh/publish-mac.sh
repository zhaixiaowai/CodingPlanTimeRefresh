#!/usr/bin/env bash
set -e
PUBLISH_APP="build/macos/Build/Products/Release/codingplan_refresh.app"
flutter build macos --release
echo "--- 体积核验 ---"
du -sh "$PUBLISH_APP"
