#!/bin/bash
# The same unsigned build and simulator journeys run locally and on hosted CI.
set -euo pipefail

cd "$(dirname "$0")/.."
family="${SALAH_IOS_SIMULATOR_FAMILY:-iPhone}"
derived_path="${SALAH_IOS_DERIVED_DATA:-.derived/ios-$family}"
run_stamp="$(date +%Y%m%d-%H%M%S)-$$"
results="$derived_path/Results/$run_stamp"
mkdir -p "$results"

# Ad-hoc simulator signing never needs an Apple Developer membership. A generic device
# build additionally catches SDK and extension integration that is device-specific.
if [[ "$family" == iPhone ]]; then
  xcodebuild build -jobs 4 -project Salah.xcodeproj -scheme SalahIOS -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$derived_path" \
    CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=
  test -d "$derived_path/Build/Products/Release-iphoneos/SalahIOS.app/PlugIns/SalahIOSWidgets.appex"
  test -f "$derived_path/Build/Products/Release-iphoneos/SalahIOS.app/NOTICE"
  # The watch app ships inside the iPhone app.
  test -d "$derived_path/Build/Products/Release-iphoneos/SalahIOS.app/Watch/SalahWatch.app"
  app_info="$derived_path/Build/Products/Release-iphoneos/SalahIOS.app/Info.plist"
  icon_name="$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw \
    -o - "$app_info" 2>/dev/null || plutil -extract CFBundleIconName raw -o - "$app_info")"
  test "$icon_name" = Salah
fi

selection="$(xcrun simctl list --json runtimes devicetypes \
  | python3 scripts/select-ios-simulator.py "$family")"
IFS=$'\t' read -r runtime device_type <<< "$selection"
simulator_id="$(xcrun simctl create "Salah iOS validation $family $$" "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id"
}
trap cleanup EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl location "$simulator_id" set 21.4225,39.8262

# iPhone Duo starts closed, on its outer display, where its journeys run.
case "$family" in
  iPad) core_class=IOSIPadJourneys ;;
  Duo) core_class=IOSDuoJourneys ;;
  *) core_class=IOSCoreJourneys ;;
esac

xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahIOS \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Unit.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahIOSUITests \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -only-testing:"SalahIOSUITests/$core_class" \
  -parallel-testing-enabled NO -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Journeys.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

# Xcode embeds these simulated entitlements in the simulator executable; its
# ad-hoc code signature can legitimately have an empty entitlement dictionary.
simulated_entitlements="$derived_path/Build/Intermediates.noindex/Salah.build/Debug-iphonesimulator/SalahIOS.build/SalahIOS.app-Simulated.xcent"
cp "$simulated_entitlements" "$results/AppEntitlements.plist"
python3 - "$results/AppEntitlements.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    entitlements = plistlib.load(source)
if entitlements.get("com.apple.developer.usernotifications.time-sensitive") is not True:
    sys.exit("The built app is missing its Time Sensitive notification entitlement.")
if "group.io.github.salah-kit.Salah" not in entitlements.get("com.apple.security.application-groups", []):
    sys.exit("The built app is missing its shared App Group entitlement.")
PY

# Notification authorization belongs to the installed app, not its preferences.
# Each permission journey must see a genuinely fresh system alert. Reinstall only
# this task's app between cases; never reset permissions on another simulator.
for permission_test in \
  testNotificationDeniedKeepsManualCityAndCompletesSetup \
  testLocationAndNotificationsAllowCompleteSetup \
  testSettingsPermissionGrantSchedulesSavedAlertsImmediately \
  testDeniedNotificationsRecoverFromSystemSettings; do
  xcrun simctl uninstall "$simulator_id" io.github.salah-kit.Salah.iOS
  xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahIOSUITests \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -only-testing:"SalahIOSUITests/IOSPermissionJourneys/$permission_test" \
    -parallel-testing-enabled NO -derivedDataPath "$derived_path" \
    -resultBundlePath "$results/$permission_test.xcresult" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
done

# Exercise production composition with its real App Group and no Debug fixture
# or test-preferences overrides, after a fresh install of this task's app.
xcrun simctl uninstall "$simulator_id" io.github.salah-kit.Salah.iOS
xcodebuild test -jobs 4 -project Salah.xcodeproj -scheme SalahIOSUITests \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -only-testing:SalahIOSUITests/IOSProductionJourneys \
  -parallel-testing-enabled NO -derivedDataPath "$derived_path" \
  -resultBundlePath "$results/Production.xcresult" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
