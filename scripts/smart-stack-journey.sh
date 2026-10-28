#!/bin/bash
# The complication outside the app (CONTRIBUTING.md, watchOS): on a new watch simulator,
# the watch app mirrors a fixture's preferences, the journey adds Salah's widget to the
# Smart Stack, and the extension's log has to show the timeline it built from them.
#
# Usage: scripts/smart-stack-journey.sh [derived data path]
set -euo pipefail

cd "$(dirname "$0")/.."
derived_path="${1:-.derived/smartstack}"
results="$derived_path/Results/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$results"

selection="$(xcrun simctl list --json runtimes devicetypes \
  | python3 scripts/select-watchos-simulator.py)"
IFS=$'\t' read -r runtime device_type <<< "$selection"
simulator_id="$(xcrun simctl create "Salah Smart Stack journey $$" "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id"
}
trap cleanup EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
started="$(date '+%Y-%m-%d %H:%M:%S')"

# TEST_RUNNER_ passes the variable to the test runner without the prefix.
TEST_RUNNER_SALAH_WATCH_SMART_STACK=1 xcodebuild test -jobs 4 -project Salah.xcodeproj \
  -scheme SalahWatchUITests -destination "platform=watchOS Simulator,id=$simulator_id" \
  -only-testing:SalahWatchUITests/WatchSmartStackJourneys \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" -resultBundlePath "$results/SmartStack.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

xcrun simctl spawn "$simulator_id" log show --style compact --start "$started" \
  --predicate 'subsystem == "io.github.salah-kit.Salah.iOS.watchkitapp.Widgets"' \
  > "$results/extension.log" || true
cat "$results/extension.log"
if ! grep -q "entries, first schedule" "$results/extension.log"; then
  echo "The extension built no timeline from the watch's settings." >&2
  exit 1
fi
