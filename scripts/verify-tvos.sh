#!/bin/bash
# The same unsigned build and simulator journeys run locally and on hosted CI.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/identity.sh
derived_path="${SALAH_TVOS_DERIVED_DATA:-.derived/tvos}"
run_stamp="$(date +%Y%m%d-%H%M%S)-$$"
results="$derived_path/Results/$run_stamp"
mkdir -p "$results"

# Ad-hoc simulator signing never needs an Apple Developer membership. A generic device
# build additionally catches SDK and extension integration that is device-specific.
xcodebuild build -jobs 4 -project Salah.xcodeproj -scheme SalahTV -configuration Release \
  -destination 'generic/platform=tvOS' -derivedDataPath "$derived_path" \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= "${identity[@]}"
app="$derived_path/Build/Products/Release-appletvos/SalahTV.app"
test -d "$app/PlugIns/SalahTVTopShelf.appex"
test -f "$app/NOTICE"
# Both bundles carry Salah's identifier and name the App Group their code reads.
python3 scripts/check-identity.py "$app_group" "$app=$bundle_identifier" \
  "$app/PlugIns/SalahTVTopShelf.appex=$bundle_identifier.tvOS.TopShelf"
# actool succeeds silently without the brand assets, so check the app names them.
test "$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon raw -o - "$app/Info.plist")" \
  = "App Icon"
test "$(plutil -extract TVTopShelfImage.TVTopShelfPrimaryImageWide raw -o - \
  "$app/Info.plist")" = "Top Shelf Image Wide"

selection="$(xcrun simctl list --json runtimes devicetypes \
  | python3 scripts/select-tvos-simulator.py)"
IFS=$'\t' read -r runtime device_type <<< "$selection"
simulator_id="$(xcrun simctl create "Salah tvOS validation $$" "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id"
}
trap cleanup EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl location "$simulator_id" set 21.4225,39.8262

# The tvOS simulator's remote daemon can crash while an app is reinstalled. That doesn't
# fail a test, but it makes xcodebuild gather simulator diagnostics for up to ten minutes;
# the result bundles keep each failure and screenshot without them.

xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahTV \
  -destination "platform=tvOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Unit.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= "${identity[@]}"
xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahTVUITests \
  -destination "platform=tvOS Simulator,id=$simulator_id" \
  -only-testing:SalahTVUITests/TVCoreJourneys \
  -only-testing:SalahTVUITests/TVTopShelfJourneys \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Journeys.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= "${identity[@]}"

# Xcode embeds these simulated entitlements in the simulator executables; their ad-hoc
# code signatures can legitimately have an empty entitlement dictionary. The app writes
# the settings the Top Shelf extension reads through the shared App Group.
intermediates="$derived_path/Build/Intermediates.noindex/Salah.build/Debug-appletvsimulator"
cp "$intermediates/SalahTV.build/SalahTV.app-Simulated.xcent" "$results/AppEntitlements.plist"
cp "$intermediates/SalahTVTopShelf.build/SalahTVTopShelf.appex-Simulated.xcent" \
  "$results/TopShelfEntitlements.plist"
simulator_app="$derived_path/Build/Products/Debug-appletvsimulator/SalahTV.app"
python3 scripts/check-identity.py "$app_group" \
  "$results/AppEntitlements.plist" "$results/TopShelfEntitlements.plist" \
  "$simulator_app=$bundle_identifier" \
  "$simulator_app/PlugIns/SalahTVTopShelf.appex=$bundle_identifier.tvOS.TopShelf"

# Each permission journey resets Salah's location authorization, so it answers a fresh
# system alert, and finds the simulated location set above.
xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahTVUITests \
  -destination "platform=tvOS Simulator,id=$simulator_id" \
  -only-testing:SalahTVUITests/TVPermissionJourneys \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Permissions.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= "${identity[@]}"

# Exercise production composition with its own defaults and no Debug fixture or
# test-preferences overrides, after a fresh install of this task's app.
xcrun simctl uninstall "$simulator_id" "$bundle_identifier"
xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahTVUITests \
  -destination "platform=tvOS Simulator,id=$simulator_id" \
  -only-testing:SalahTVUITests/TVProductionJourneys \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Production.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= "${identity[@]}"
