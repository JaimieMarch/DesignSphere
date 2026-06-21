#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${DESIGNSPHERE_TEST_DESTINATION:-platform=visionOS Simulator,name=Apple Vision Pro,OS=latest}"
DERIVED_DATA_ROOT="${TMPDIR:-/tmp}/DesignSphereTests"

python3 -m unittest discover -s "$ROOT/Tools/catalog-pipeline/tests" -v

(
    cd "$ROOT/Packages/XRShareCollaboration"
    xcodebuild test \
        -scheme XRShareCollaboration \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA_ROOT/Package" \
        CODE_SIGNING_ALLOWED=NO
)

xcodebuild test \
    -project "$ROOT/Demo App.xcodeproj" \
    -scheme "Demo App Vision" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_ROOT/App" \
    CODE_SIGNING_ALLOWED=NO
