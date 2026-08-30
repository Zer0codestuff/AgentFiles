#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTIVE_DEVELOPER_DIR="$(xcode-select -p)"
TEST_FRAMEWORKS="$ACTIVE_DEVELOPER_DIR/Library/Developer/Frameworks"
TEST_LIBS="$ACTIVE_DEVELOPER_DIR/Library/Developer/usr/lib"

cd "$ROOT_DIR"

if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    swift test \
        --enable-swift-testing \
        --disable-xctest \
        -Xswiftc -F \
        -Xswiftc "$TEST_FRAMEWORKS" \
        -Xlinker -rpath \
        -Xlinker "$TEST_FRAMEWORKS" \
        -Xlinker -rpath \
        -Xlinker "$TEST_LIBS"
else
    swift test --enable-swift-testing --disable-xctest
fi
