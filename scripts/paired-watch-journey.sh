#!/bin/bash
# The preferences' way from the iPhone app to the watch app, on an iPhone simulator paired
# with a watch simulator (CONTRIBUTING.md, watchOS):
#
#   1. build the iPhone app, with the watch app inside, and the watch journeys
#   2. boot the pair, and install the iPhone app and the watch app fresh
#   3. set Salah up on the iPhone from a fixture at the Kaaba; it sends the preferences
#   4. on the watch, a launch with no preferences of its own waits for the iPhone's, then
#      shows the Kaaba's Qibla, and keeps them across a relaunch
#
# Usage: scripts/paired-watch-journey.sh <iPhone UDID> <Watch UDID> [derived data path]
# Create and pair the simulators first. The script shuts them down at the end; results go
# to <derived data>/Results.
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ $# -lt 2 ]]; then
  echo "usage: $0 <iPhone UDID> <Watch UDID> [derived data path]" >&2
  exit 2
fi
phone="$1"
watch="$2"
derived_path="${3:-.derived/paired}"
results="$derived_path/Results/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$results"

shutdown() {
  xcrun simctl shutdown "$phone" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$watch" >/dev/null 2>&1 || true
}
trap shutdown EXIT

xcodebuild build -jobs 4 -project Salah.xcodeproj -scheme SalahIOS \
  -destination "id=$phone" -derivedDataPath "$derived_path" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
xcodebuild build-for-testing -jobs 4 -project Salah.xcodeproj -scheme SalahWatchUITests \
  -destination "id=$watch" -derivedDataPath "$derived_path" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

xcrun simctl boot "$phone" 2>/dev/null || true
xcrun simctl boot "$watch" 2>/dev/null || true
xcrun simctl bootstatus "$phone" -b
xcrun simctl bootstatus "$watch" -b
xcrun simctl list pairs | grep -B1 -A2 "$watch"

xcrun simctl uninstall "$watch" io.github.salah-kit.Salah.iOS.watchkitapp 2>/dev/null || true
xcrun simctl uninstall "$phone" io.github.salah-kit.Salah.iOS 2>/dev/null || true
xcrun simctl install "$phone" "$derived_path/Build/Products/Debug-iphonesimulator/SalahIOS.app"
xcrun simctl install "$watch" "$derived_path/Build/Products/Debug-watchsimulator/SalahWatch.app"

# Salah on the iPhone, set up at the Kaaba from its fixture, sends the preferences once its
# session is active, and stays open to answer the watch's request.
xcrun simctl launch "$phone" io.github.salah-kit.Salah.iOS \
  -salah.ios.testSuite paired -salah.ios.reset true -salah.ios.fixture true \
  -salah.ios.skipOnboarding true
sleep 10

# TEST_RUNNER_ passes the variable to the test runner without the prefix.
TEST_RUNNER_SALAH_WATCH_PAIRED=1 xcodebuild test-without-building -project Salah.xcodeproj \
  -scheme SalahWatchUITests -destination "id=$watch" \
  -only-testing:SalahWatchUITests/WatchPairedJourneys \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" -resultBundlePath "$results/Paired.xcresult"
