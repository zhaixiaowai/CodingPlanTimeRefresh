#!/bin/bash
cd "$(dirname "$0")"

cleanup_language_folders() {
    local publish_dir="$1"
    echo "Cleaning up language folders in $publish_dir..."
    cd "$publish_dir" || return 1
    for dir in *-*; do
        case "$dir" in
            en-*|zh-CN|zh-Hans|zh-Hant|zh-TW) ;;
            *) rm -rf "$dir" ;;
        esac
    done
    for dir in ??; do
        case "$dir" in
            en) ;;
            *) rm -rf "$dir" ;;
        esac
    done
    cd - > /dev/null
}

BIN_DIR="CodingPlanTimeRefresh/bin/Release/net10.0-maccatalyst"
PUBLISH_DIR="$BIN_DIR/publish"
echo "=== Publishing for Universal ==="
rm -rf "$BIN_DIR"/*
dotnet publish CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-maccatalyst -c Release /p:CreatePackage=false
if [ $? -ne 0 ]; then
    echo "Publish failed for Universal."
    read
    exit 1
fi
cleanup_language_folders "$PUBLISH_DIR"
echo "=== Universal done ==="
echo

echo "All done. Press Enter to exit."
read
