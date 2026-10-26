# iOS app journeys

These XCUITests drive the installed app. Their Debug launch options isolate durable
preferences without replacing city search, calculation, permission requests or navigation.
Every launch uses its own suite; a relaunch retains that suite so a reconstruction has to
read the saved changes. Screenshots are kept as result-bundle attachments.

- `IOSCoreJourneys` covers city search, saved calculation and independent notification
  preferences, global mute, day/week navigation, missing-location recovery, Arabic RTL,
  dark appearance, accessibility text sizes, and explicit prayer playback/stop.
- `IOSIPadJourneys` covers the regular-width layout in landscape and first-run form-sheet
  geometry over the app. Run it on an iPad.
- `IOSDuoJourneys` covers iPhone Duo's outer display: its side bar holds the tabs, Back and
  icon controls beside the content, in English and Arabic. Run it on iPhone Duo, closed.
- `IOSDuoPoseJourneys` covers the poses XCTest can't choose: the tent, and the open display
  on its side and upright, where screens with two pages keep the fold empty. Choose each
  pose in Device Hub first ([CONTRIBUTING](../CONTRIBUTING.md#ios-and-ipados)); each test
  skips unless the simulator is in its pose.
- `IOSProductionJourneys` completes first-run setup and verifies shared-container
  persistence without Debug launch overrides. Run it after a fresh installation.
- `IOSPermissionJourneys` answers the actual SpringBoard alerts and completes onboarding.
  Run each method separately after a fresh app installation, since XCTest cannot reset
  iOS notification authorization. The allow journey needs a simulated location, for example
  latitude `21.4225`, longitude `39.8262`. Neither journey grants consent through a fixture.

Run the following permission methods independently, reinstalling the app between them:

```text
SalahIOSUITests/IOSPermissionJourneys/testNotificationDeniedKeepsManualCityAndCompletesSetup
SalahIOSUITests/IOSPermissionJourneys/testLocationAndNotificationsAllowCompleteSetup
SalahIOSUITests/IOSPermissionJourneys/testSettingsPermissionGrantSchedulesSavedAlertsImmediately
SalahIOSUITests/IOSPermissionJourneys/testDeniedNotificationsRecoverFromSystemSettings
```

The city journeys use Apple's live search and need a network connection. Prayer arithmetic,
notification content/planning, stale results and repository failures are tested below the UI;
these journeys observe the production construction and interaction boundaries instead.
