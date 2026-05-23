#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${CARELOOP_IOS_ROOT:-}" ]]; then
  IOS_DIR="$(cd "$CARELOOP_IOS_ROOT" && pwd)"
elif [[ -d "$PROJECT_DIR/ios/CareLoop.xcodeproj" ]]; then
  IOS_DIR="$(cd "$PROJECT_DIR/ios" && pwd)"
elif [[ -d "$PROJECT_DIR/../careloop-ios/CareLoop.xcodeproj" ]]; then
  IOS_DIR="$(cd "$PROJECT_DIR/../careloop-ios" && pwd)"
elif [[ -d "$PROJECT_DIR/../ios/CareLoop.xcodeproj" ]]; then
  IOS_DIR="$(cd "$PROJECT_DIR/../ios" && pwd)"
else
  echo "CareLoop iOS project not found. Set CARELOOP_IOS_ROOT or place it at ./ios, ../careloop-ios, or ../ios." >&2
  exit 66
fi
DESTINATION="${CARELOOP_XCODE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
API_BASE_URL="${CARELOOP_API_BASE_URL:-http://127.0.0.1:3000}"
RUNTIME_DIR="$PROJECT_DIR/.tmp"
API_LOG="$RUNTIME_DIR/careloop-ios-test-api.log"
MANIFEST_PATH="$RUNTIME_DIR/careloop-ios-test-showcase-manifest.json"
API_PID=""

export DEVELOPER_DIR

usage() {
  cat <<'USAGE'
Usage:
  scripts/careloop-ios-test-runner.sh <suite>

Suites:
  list       Show this help.
  ios        Full Xcode suite with API + demo seed prepared first.
  ios:ui     Full CareLoopUITests target with API + demo seed prepared first.
  ios:api    API-backed demo and persona UI journeys only.

Environment:
  CARELOOP_XCODE_DESTINATION overrides the simulator destination.
  CARELOOP_API_BASE_URL overrides the local API health URL.
USAGE
}

healthcheck() {
  curl --fail --silent --show-error "$API_BASE_URL/health" >/dev/null 2>&1
}

wait_for_api() {
  local timeout_seconds="${1:-45}"
  local started_at
  started_at="$(date +%s)"

  until healthcheck; do
    if (( "$(date +%s)" - started_at >= timeout_seconds )); then
      echo "CareLoop API was not healthy within ${timeout_seconds}s. Check $API_LOG" >&2
      return 1
    fi
    sleep 1
  done
}

ensure_api_running() {
  mkdir -p "$RUNTIME_DIR"
  if healthcheck; then
    echo "CareLoop API already healthy at $API_BASE_URL"
    return
  fi

  echo "Starting CareLoop API for API-backed iOS tests..."
  (
    cd "$PROJECT_DIR"
    npm run start
  ) >"$API_LOG" 2>&1 &
  API_PID="$!"
  wait_for_api 60
}

cleanup() {
  if [[ -n "$API_PID" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

seed_showcase() {
  echo "Seeding CareLoop showcase data for API-backed iOS tests..."
  (
    cd "$PROJECT_DIR"
    npm run qa:seed:showcase
  ) >"$MANIFEST_PATH"
}

prepare_api_backed_ios() {
  ensure_api_running
  seed_showcase
  wait_for_api 15
}

run_xcode() {
  xcodebuild test \
    -project "$IOS_DIR/CareLoop.xcodeproj" \
    -scheme CareLoop \
    -destination "$DESTINATION" \
    "$@"
}

suite="${1:-list}"

case "$suite" in
  list)
    usage
    ;;
  ios)
    prepare_api_backed_ios
    run_xcode
    ;;
  ios:ui)
    prepare_api_backed_ios
    run_xcode -only-testing:CareLoopUITests
    ;;
  ios:api)
    prepare_api_backed_ios
    run_xcode \
      -only-testing:CareLoopUITests/CareLoopUITests/test_adminEndToEndDemoFlow \
      -only-testing:CareLoopUITests/CareLoopUITests/test_recordingOrganizerRealWorldJourney \
      -only-testing:CareLoopUITests/CareLoopUITests/test_recordingCaregiverRealWorldJourney \
      -only-testing:CareLoopUITests/CareLoopUITests/test_recordingCareReceiverRealWorldJourney \
      -only-testing:CareLoopUITests/CareLoopUITests/test_recordingMemoryCaregiverRealWorldJourney
    ;;
  *)
    echo "Unknown suite: $suite" >&2
    echo >&2
    usage >&2
    exit 64
    ;;
esac
