#!/bin/bash
# Run unit tests for MeetingRecorder
# Usage: ./scripts/run-tests.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🧪 Running MeetingRecorder Tests..."
echo ""

# Build and test using xcodebuild
xcodebuild test \
    -project MeetingRecorder.xcodeproj \
    -scheme MeetingRecorderTests \
    -destination 'platform=macOS' \
    -resultBundlePath TestResults.xcresult \
    | xcpretty || true

echo ""
echo "✅ Tests complete!"
echo "Results saved to TestResults.xcresult"
