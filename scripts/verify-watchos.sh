#!/bin/bash
# The same unsigned build and simulator journeys run locally and on hosted CI.
set -euo pipefail

cd "$(dirname "$0")/.."
derived_path="${SALAH_WATCHOS_DERIVED_DATA:-.derived/watchos}"
run_stamp="$(date +%Y%m%d-%H%M%S)-$$"
results="$derived_path/Results/$run_stamp"
mkdir -p "$results"

# Ad-hoc simulator signing never needs an Apple Developer membership. A generic device
# build additionally catches SDK and extension integration that is device-specific.
xcodebuild build -jobs 4 -project Salah.xcodeproj -scheme SalahWatch -configuration Release \
  -destination 'generic/platform=watchOS' -derivedDataPath "$derived_path" \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=
app="$derived_path/Build/Products/Release-watchos/SalahWatch.app"
test -d "$app/PlugIns/SalahWatchWidgets.appex"
test -f "$app/adhan-ahmed-khalaf.mp3"
# The iPhone app owns the preferences: the watch app installs with it.
test "$(plutil -extract WKCompanionAppBundleIdentifier raw -o - "$app/Info.plist")" \
  = io.github.salah-kit.Salah.iOS
# actool succeeds silently without the icon, so check the app names it.
icon_name="$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw \
  -o - "$app/Info.plist" 2>/dev/null || plutil -extract CFBundleIconName raw -o - "$app/Info.plist")"
test "$icon_name" = Salah

selection="$(xcrun simctl list --json runtimes devicetypes \
  | python3 scripts/select-watchos-simulator.py)"
IFS=$'\t' read -r runtime device_type <<< "$selection"
simulator_id="$(xcrun simctl create "Salah watchOS validation $$" "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id"
}
trap cleanup EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b

xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahWatch \
  -destination "platform=watchOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Unit.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahWatchUITests \
  -destination "platform=watchOS Simulator,id=$simulator_id" \
  -only-testing:SalahWatchUITests/WatchCoreJourneys \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Journeys.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

# Xcode embeds these simulated entitlements in the simulator executables; their ad-hoc
# code signatures can legitimately have an empty entitlement dictionary. The app writes
# the settings the complications read through the watch's App Group.
intermediates="$derived_path/Build/Intermediates.noindex/Salah.build/Debug-watchsimulator"
cp "$intermediates/SalahWatch.build/SalahWatch.app-Simulated.xcent" \
  "$results/AppEntitlements.plist"
cp "$intermediates/SalahWatchWidgets.build/SalahWatchWidgets.appex-Simulated.xcent" \
  "$results/WidgetsEntitlements.plist"
python3 - "$results/AppEntitlements.plist" "$results/WidgetsEntitlements.plist" <<'PY'
import plistlib
import sys

for path in sys.argv[1:]:
    with open(path, "rb") as source:
        entitlements = plistlib.load(source)
    if "group.io.github.salah-kit.Salah" not in entitlements.get(
        "com.apple.security.application-groups", []
    ):
        sys.exit(f"{path} is missing the shared App Group entitlement.")
PY

# Exercise production composition with its own defaults and no Debug fixture, after a
# fresh install of this task's app: it waits for the iPhone.
xcrun simctl uninstall "$simulator_id" io.github.salah-kit.Salah.iOS.watchkitapp
xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahWatchUITests \
  -destination "platform=watchOS Simulator,id=$simulator_id" \
  -only-testing:SalahWatchUITests/WatchProductionJourneys \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Production.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
