# tvOS architecture

The Apple TV app and its Top Shelf extension use SalahKit's released public APIs, like the
iPhone and iPad app. Prayer calculation and schedule semantics stay in the packages. The
app compiles the iOS app's preferences, store and city search, and owns what is particular
to a television: focus navigation with the Siri Remote, the room display, the adhan while
Salah is open, and the Top Shelf. Each device keeps its own settings; nothing syncs.

## Responsibilities

| Layer | Responsibility |
|---|---|
| [`SalahTV/App`](../SalahTV/App) | Constructs the store and platform services in [`TVAppRuntime`](../SalahTV/App/TVAppRuntime.swift), connects their callbacks, runs the clock while the app is active, and handles scene activation and time changes. [`TVNavigation`](../SalahTV/App/TVNavigation.swift) owns the tabs, the Settings path, the full-screen room display and adhan, and links such as `salah://room`. |
| [`SalahTV/Domain`](../SalahTV/Domain) | Turns the display state into the hero, rows and notes the screens show, and maps each prayer's sound onto the iOS preferences. |
| [`SalahTV/Data`](../SalahTV/Data) | Adapts Core Location and MapKit, audio playback and the remote's media commands, SalahAlerts' in-process alerts, the idle timer and the Top Shelf reload. |
| [`SalahTV/DesignSystem`](../SalahTV/DesignSystem) | The focus platter and the prayer row, hero and board cell. Feature views supply state and actions. |
| [`SalahTV/Features`](../SalahTV/Features) | Today, Week, Settings, the room display, the adhan, setup and city search. |
| [`SalahTVShared`](../SalahTVShared) | The theme, wording helpers, the day ribbon and the Top Shelf's snapshot and banner views, compiled into the app, the extension and the tests, with the app's String Catalog. |
| [`SalahTVTopShelf`](../SalahTVTopShelf) | The Top Shelf content provider. It reads the settings the app mirrors and never needs the app to run. |

The app compiles the iOS app's [`IOSAppStore`](../SalahIOS/Domain/IOSAppStore.swift),
[`IOSPreferences`](../SalahIOSShared/IOSPreferences.swift),
[`IOSPreferencesRepository`](../SalahIOS/Data/IOSPreferencesRepository.swift),
[`IOSCitySearchService`](../SalahIOS/Data/Location/IOSCitySearchService.swift),
[`IOSMapLocation`](../SalahIOS/Data/Location/IOSMapLocation.swift) and
[`IOSAudioFiles`](../SalahIOS/Data/Audio/IOSAudioFiles.swift) unchanged, with the portable
models in [`Shared`](../Shared) and the iOS asset catalog's semantic colors. A change to
one of those files is a change to both apps; the tvOS build and journeys check it.

## Preferences and the Top Shelf mirror

tvOS keeps only an app's defaults across launches: its caches can be cleared whenever the
system needs space. So preferences use the iOS repository's `UserDefaults` storage in the
app's standard defaults, not the App Group file the iOS app uses. Setup ends when there is
a location: this Apple TV's, found once with When In Use permission (Allow Once is enough,
because an Apple TV doesn't move), or a city from Apple Maps search, which needs no
permission. The calculation method follows the country, as on iOS.

The app mirrors its `SalahSettings` into the App Group `group.io.github.salah-kit.Salah`
through SalahWidgets' `SharedValue`, and asks the system to reload the Top Shelf when the
mirror, the next prayer, the day or the time of day changes. The extension builds a
snapshot for the moment the system asks, draws three inset banners (the next prayer, today's prayers and the room
display) at 1940 × 692 pt for both screen scales, and saves them in the App Group's
caches, where the system reads them. The images show times, never a ticking countdown.
Each banner links into the app: `salah://today` or `salah://room`. Without a location the
extension gives no content, and tvOS shows the static Top Shelf image from the brand
assets.

## Sound and the room display

A tvOS notification can only badge the app's icon, so the adhan plays only while Salah is
open. [`TVAdhanCoordinator`](../SalahTV/Data/TVAdhanCoordinator.swift) plans each prayer's
at-time alert with SalahAlerts' `AlertPlanner` and follows it with an
`InProcessAlertEngine` on the app's clock. When one is due, and the prayer has a sound and
sounds are on, the runtime plays it and shows the adhan screen, over the room display when
that was open; Stop, Play/Pause and Back end it, and the room display comes back. Leaving
Salah stops any sound and plans nothing until it's back, and the app has no background
audio mode. On activation, a new day or a clock change, an adhan whose prayer began in the
last five minutes still plays. A settings change never starts one for a prayer that has
already begun. The fire date of the last adhan played or passed over is kept in the
defaults, so coming back or relaunching doesn't repeat it. The sounds are the two CC BY
4.0 recordings the iOS app bundles, the generated soft tone, or none; [NOTICE](../NOTICE)
records their licenses, and About in the app reads the bundled audio notice.

The room display keeps the day's times on screen for a home or a musalla. While it or the
adhan is showing, the app turns the idle timer off so the screen saver doesn't start; an
adhan over the room display keeps it off throughout. It turns it back on when they close or
Salah leaves the screen, and off again when Salah comes back to the room display.

## Presentation and verification boundaries

Rows, day columns and Settings take focus; the hero, the board and the footers don't.
[`TVPlatterButtonStyle`](../SalahTV/DesignSystem/TVFocusPlatter.swift) draws tvOS's own
focused platter for Salah's rows, and Settings uses the system's list. Focus sections and
default focus send the remote where people expect: down from the tab bar to the next
prayer or today's column, across to Keep on Screen, and past either end of the week to
the next or previous one. At accessibility text sizes Today becomes one column that
scrolls. The selected language's locale, digits and direction apply at the root, and
the wording comes from [`Localizable.xcstrings`](../SalahTVShared/Resources/Localizable.xcstrings)
and the location reason in [`InfoPlist.xcstrings`](../SalahTV/Resources/InfoPlist.xcstrings).

[`SalahTVTests`](../SalahTVTests) exercises presentation, navigation, the adhan plan, the
Top Shelf snapshot, its images and the reload rule in a non-hosted bundle.
[`SalahTVUITests`](../SalahTVUITests) drives the installed app with the Siri Remote: the
core journeys, the Top Shelf on the Home Screen, the real location alert, and production
storage after a fresh install. [CONTRIBUTING.md](../CONTRIBUTING.md#tvos) has the
commands. A passing run doesn't establish audio on a television, the screen saver over
hours, or the remote's touch surface; the [tvOS validation notes](tvos-validation.md) list
those checks.
