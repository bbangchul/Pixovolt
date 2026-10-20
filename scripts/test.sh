#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/work/tests"
xcrun swiftc -module-cache-path "$ROOT/work/tests/Modules" -parse-as-library -target arm64-apple-macosx13.0 "$ROOT/Pixovolt/Domain.swift" "$ROOT/Pixovolt/DisplayConnection.swift" "$ROOT/Tests/Tests.swift" -o "$ROOT/work/tests/PixovoltTests"
"$ROOT/work/tests/PixovoltTests"
