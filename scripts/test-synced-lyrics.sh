#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-synced-lyrics.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/SyncedLyrics.swift tests/SyncedLyricsTests.swift -o "$TEST_DIR/synced-lyrics-tests"
"$TEST_DIR/synced-lyrics-tests"
