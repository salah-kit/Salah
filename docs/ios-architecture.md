# iOS architecture

The iPhone and iPad app and its system surfaces use SalahKit's released public APIs.
Prayer calculation and schedule semantics stay in the packages; iOS owns preferences,
navigation, native services, presentation and persistence. The macOS app keeps its own
composition and feature implementation.

## Responsibilities

| Layer | Responsibility |
|---|---|
| [`SalahIOS/App`](../SalahIOS/App) | Constructs the store and platform services, connects their callbacks, handles scene activation and time changes, and owns tab navigation and background refresh. |
| [`IOSAppStore`](../SalahIOS/Domain/IOSAppStore.swift) | Owns observable application state, onboarding, selected date, settings navigation, preference edits, derived prayer schedules, Qibla geometry and deep-link routing. It depends on the preferences repository contract. |
| [`IOSPreferences`](../SalahIOSShared/IOSPreferences.swift) | Defines app-owned choices, defaults, validation bounds and the derived `SalahSettings` mirror. It has no view or system-permission dependency. |
| [`SalahIOS/Data`](../SalahIOS/Data) | Adapts storage, Core Location, MapKit, UserNotifications, audio and ActivityKit to the app. Permissions and device capability stay here. |
| [`SalahIOS/DesignSystem`](../SalahIOS/DesignSystem) | Provides semantic color, typography, sky, prayer-row, hero, card and recovery components. Feature views supply state and actions. |
| [`SalahIOS/Features`](../SalahIOS/Features) | Presents Today, Times, Qibla, setup and settings. Features read the store and request actions from the services supplied by the app's composition root. |
| [`SalahIOSShared`](../SalahIOSShared) | Contains preferences, transactional shared storage, localization, intent and Live Activity contracts used by both iOS processes. |
| [`SalahIOSWidgets`](../SalahIOSWidgets) | Builds Home Screen and Lock Screen timelines, Live Activity and Dynamic Island presentations, and Control Center controls. It derives times from mirrored settings rather than requiring a running app. |

Portable models in [`Shared`](../Shared) provide the prayer source, display state,
settings mirror, timeline and palette. The iOS targets select these files explicitly;
macOS-only widget faces and app lifecycle code are not part of the iOS app.

## Preferences and prayer state

[`IOSPreferencesRepository`](../SalahIOS/Data/IOSPreferencesRepository.swift) is the
store's persistence boundary. Production storage is a versioned JSON file in the App
Group, owned by
[`IOSSharedPreferencesStore`](../SalahIOSShared/IOSSharedPreferencesStore.swift).
A file lock covers read, modification and write across processes; atomic replacement
protects readers. A newer schema is rejected rather than overwritten. The app merges
the fields the person edited into a fresh snapshot, preserving unrelated changes from
a Control Center intent. Failed saves keep active edits visible and surface an error.

A new installation has no location. Until a location fix or city is selected, the app
has no schedule mirror and widgets show setup. A complete location includes coordinates
and a time zone; prayer dates and displayed times use that zone. Choosing a city stops
automatic location following. City searches cancel previous requests and reject stale
responses before publishing results.

The preferences produce `CalculationSettings`, then a `SalahSettings` mirror and its
schedule. `SalahDisplay` supplies next-prayer, just-started, missing-time and tomorrow
semantics to the app and widgets. Sunrise is an optional event with an alert, rather
than a prayer that starts an approach or count-up period. Calculation stays offline.
Apple services resolve current location and city searches; Salah has no account,
analytics or sync service between devices.

## Notifications and audio

[`IOSNotificationService`](../SalahIOS/Data/Notifications/IOSNotificationService.swift)
uses SalahAlerts to plan a rolling fourteen-day schedule. It reserves space for other
app notifications and installs at most sixty prayer requests within the system budget.
Requests use the app's namespace and stable prayer identities. Replanning replaces
owned requests without withdrawing unrelated notifications; request read-back reports
installation, rather than claiming delivery or audible playback.

At-time, before and after slots have independent enablement, offsets and sound choices.
Jumu'ah inherits Dhuhr unless its Friday override is enabled. Mute silences sounds while
retaining alerts. Launch, activation, location, preference and time-zone changes replan
the schedule. A registered background refresh requests another opportunity to replenish
it; iOS determines when that opportunity occurs.
At-time content requests Time Sensitive presentation. The app target's entitlement is
generated from [`project.yml`](../project.yml); the widget target does not request it.

[`IOSAudioFiles`](../SalahIOS/Data/Audio/IOSAudioFiles.swift) copies imported recordings
into managed local storage and prepares a PCM CAF notification excerpt of at most
twenty-nine seconds. It also prepares excerpts from the bundled regular and Fajr adhan
recordings. These two recordings are licensed under CC BY 4.0; [NOTICE](../NOTICE)
records their sources and terms. The same notice is copied into the app for offline
Audio credits. The other built-in choices are the system sound, a synthesized soft tone
and no sound.
Original recordings can be at most thirty minutes long. Import rejects longer files
before copying, and playback checks the same limit again for previously stored files.
Accepted recordings play intact. The optional spoken du'a has a two-minute deadline,
and the shared playback contract covers the full session for at most thirty-two
minutes, preserving external Stop throughout that window.
[`IOSAudioService`](../SalahIOS/Data/Audio/IOSAudioService.swift) starts full playback
only from an explicit action, manages audio interruptions and remote Stop, and may
speak the optional du'a after a built-in or imported adhan. Previews stop in the background;
explicit full playback uses the audio background mode. A scheduled notification never
starts full playback.

## Widgets, controls and Live Activities

The app publishes the settings mirror and bounded playback state into the App Group.
The widget extension computes its own schedule and timeline. Setup, missing times and
expired timelines have explicit recovery presentations; an expired entry does not keep
counting toward an old prayer. Widget links route into the appropriate app destination.

[`IOSActivityCoordinator`](../SalahIOS/Data/Activities/IOSActivityCoordinator.swift)
starts relevant prayer Live Activities while the app is foregrounded. Activity content
contains its own validity deadline, so a suspended app does not promise indefinite
updates. A dismissed prayer is not immediately recreated. Playing state requires an
actual user-started playback session. Compact presentations show status; Stop is an
interactive action in the presentations that support it.

Control Center mute changes use the canonical preferences transaction and refresh the
notification plan in the app process. Stop clears shared playback and signals the
running audio owner. The shared contracts define these actions; the extension does not
construct the app's views or own its audio player.

## iPhone Duo

iPhone Duo has two displays. Closed, its outer display has a vertical bar along one long
edge. The system moves the tab bar, Back and icon toolbar items, such as Times' calendar,
into it. Beside the bar, Salah's screens use the system's container margins rather than
the design system's 16 points.

Open, the inner display has a fold.
[`IOSDisplayGeometryReader`](../SalahIOS/DesignSystem/IOSDisplayGeometry.swift) reads the
hinge's division region, including it while it's inactive, so a flat and a folded device
report the same 40-point region. [`IOSFoldLayout`](../SalahIOS/DesignSystem/IOSFoldLayout.swift)
divides a screen into the pages on either side of it. On its side:

- Today shows the next prayer on one page and the day's prayers on the other.
- Times shows the date on one page and the day or week choice on the other. The week
  table's columns leave the fold between Dhuhr and Asr. At accessibility text sizes Times
  keeps to the first page, and without a location its recovery does.
- Qibla shows the dial beside its facts.
- Settings shows the list beside the selected pane.

In right-to-left languages the first page is the one beside the bar. Upright, Today and
Qibla put their pages above and below the fold, and while a prayer sound plays Today's
lower page starts with Stop; Times and Settings scroll through the fold as on a taller
display. Folding or unfolding moves nothing. The system's split containers meet the fold only while
it's folded, so these screens lay out around the region themselves. Live Activities read
`isDynamicIslandLimitedInWidth` and draw one 28-point view in the vertical Dynamic Island,
leaving the trailing view empty.

## Presentation and verification boundaries

Semantic assets in [`SalahIOS/Assets.xcassets`](../SalahIOS/Assets.xcassets) and
[`IOSTheme`](../SalahIOS/DesignSystem/IOSTheme.swift) keep light, dark, contrast and prayer
phase styling out of feature logic. Native navigation and controls provide the platform
behavior. Localized app and extension copy comes from the iOS String Catalogs and
[`IOSL10n`](../SalahIOSShared/IOSLocalization.swift); selected-language locale and layout
direction are applied at the view root.

[`SalahIOSTests`](../SalahIOSTests) exercises logic and adapter contracts in a non-hosted
simulator bundle. [`SalahIOSUITests`](../SalahIOSUITests) drives the constructed app,
including persistence across relaunch, phone and tablet navigation, iPhone Duo's displays,
Arabic layout and real permission alerts. Each permission case requires a fresh app installation.
[CONTRIBUTING.md](../CONTRIBUTING.md#ios-and-ipados) defines the build and journey commands.
These source boundaries describe what the tests target; a passing run does not establish
physical compass accuracy, eventual background scheduling or App Store availability.
The [iOS validation notes](ios-validation.md) describe the reproducible checks,
remaining contributor reviews and system limitations.
