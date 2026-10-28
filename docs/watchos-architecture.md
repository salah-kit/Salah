# watchOS architecture

The Apple Watch app is the iPhone app's companion. It ships inside the iPhone app, takes its
preferences from it, and keeps its own copy, so it calculates and shows the times while the
iPhone app is closed or the iPhone is away. Prayer calculation and schedule semantics stay in
the packages. The app compiles the iOS app's preferences, store and wording, and owns what is
particular to a wrist: the pages the Digital Crown moves through, the watch's compass, the
adhan while Salah is open, and the complications.

## Responsibilities

| Layer | Responsibility |
|---|---|
| [`SalahWatch/App`](../SalahWatch/App) | Constructs the store and platform services in [`WatchAppRuntime`](../SalahWatch/App/WatchAppRuntime.swift), connects their callbacks, runs the clock, and handles scene activation, time changes and the background delivery of the iPhone's preferences. [`WatchNavigation`](../SalahWatch/App/WatchNavigation.swift) owns the page and links such as `salah://today`. |
| [`SalahWatch/Domain`](../SalahWatch/Domain) | Turns the display state into the hero, the rows and what VoiceOver reads, on the iPhone app's [`IOSPrayerPresentation`](../SalahIOS/Features/Today/IOSPrayerPresentation.swift), and the Qibla bearing and compass into the dial's states. |
| [`SalahWatch/Data`](../SalahWatch/Data) | Receives the preferences over WatchConnectivity, reads the compass, plays the adhan and plans it with SalahAlerts' in-process engine, publishes the settings the complications read, and presents the iPhone's notifications while Salah is frontmost. |
| [`SalahWatch/DesignSystem`](../SalahWatch/DesignSystem) | The hero, the prayer row and the Qibla dial. Feature views supply state and actions. |
| [`SalahWatch/Features`](../SalahWatch/Features) | The first page with the next prayer, Today, Qibla, and the setup page shown until the iPhone sends its preferences. |
| [`SalahWatchShared`](../SalahWatchShared) | The theme, the wording helper and the complication's kind, compiled into the app, the complications and the tests, with the watch's String Catalog. |
| [`SalahWatchWidgets`](../SalahWatchWidgets) | The complications and the Smart Stack widget. They read the settings the app mirrors and never need the app to run. |

The app compiles the iOS app's [`IOSAppStore`](../SalahIOS/Domain/IOSAppStore.swift),
[`IOSPreferences`](../SalahIOSShared/IOSPreferences.swift),
[`IOSPreferencesRepository`](../SalahIOS/Data/IOSPreferencesRepository.swift),
[`IOSPrayerPresentation`](../SalahIOS/Features/Today/IOSPrayerPresentation.swift) and
[`IOSAudioFiles`](../SalahIOS/Data/Audio/IOSAudioFiles.swift) unchanged, and the
complications compile the Lock Screen's
[`IOSAccessoryCopy`](../SalahIOSWidgets/IOSAccessoryCopy.swift) and
[`PrayerGlyph`](../SalahIOSWidgets/PrayerGlyph.swift). A change to one of those files is a
change to both apps; the watch build and journeys check it.

## Preferences from the iPhone

The iPhone app's [`IOSWatchSync`](../SalahIOS/Data/Watch/IOSWatchSync.swift) sends the whole
`IOSPreferences` as JSON under the versioned key `preferences.v1`, with the instant it sent
them ([`WatchPreferencesMessage`](../SalahIOSShared/WatchPreferencesMessage.swift)). It sends
them as the session's application context, which keeps only the latest and which the system
delivers when the watch app next runs, in the background if need be: on launch and
activation, after every change, after a background refresh, and again, under a new date,
when the watch app is installed. Before setup there's no location, so it sends nothing. It
doesn't send what the watch already has.

The watch's [`WatchPreferencesReceiver`](../SalahWatch/Data/WatchPreferencesReceiver.swift)
keeps a context only when it was sent after the preferences the watch has, so a context read
again at launch, or a late reply, never replaces newer ones. While the watch has no
preferences and the iPhone is reachable, it asks the iPhone app for them with a message; iOS
wakes Salah on the iPhone to answer. Until preferences arrive, the watch shows where to set
Salah up, and so do the complications.

The watch stores its copy in its own defaults through the iOS repository, and mirrors its
`SalahSettings` into its App Group, `group.io.github.salah-kit.Salah` on the watch, through
SalahWidgets' `SharedValue`, reloading the complications when the mirror changes. A watch's
App Group isn't shared with the iPhone: nothing on the iPhone reads it.

## Alerts and the adhan

The iPhone app schedules the alerts. iOS shows a local notification on the watch instead of
the iPhone when the iPhone is locked and the watch is on a wrist and unlocked, so the watch
schedules none of its own: two apps scheduling the same prayer would alert twice. When one
arrives while Salah is the frontmost app, watchOS asks Salah how to present it, and Salah
shows it as anywhere else, unless the watch is already playing that adhan.

While Salah is open, [`WatchAdhanCoordinator`](../SalahWatch/Data/WatchAdhanCoordinator.swift)
plans each prayer whose alert is on with SalahAlerts' `AlertPlanner` and follows it with an
`InProcessAlertEngine` on the app's clock, as the Apple TV app does. When one is due and
sounds aren't muted, [`WatchAudioService`](../SalahWatch/Data/WatchAudioService.swift) plays
the regular or Fajr adhan, or the soft tone for a system sound or an imported recording,
which the watch doesn't have, followed by the spoken du'a when it's on; the first page shows
it with Stop. With the wrist down Salah stays frontmost and the adhan plays on; when Salah
leaves the screen the sound stops and nothing is planned until it's back. On activation, a
new day or a clock change, an adhan whose prayer began in the last five minutes still plays.
Preferences from the iPhone never start one for a prayer that has already begun. The fire
date of the last adhan played or passed over is kept in the defaults, so coming back or
relaunching doesn't repeat it. [NOTICE](../NOTICE) records the recordings' licenses.

## The screens

Salah's watch design is always dark. The watchOS asset compiler keeps one appearance of a
color set, so the watch reads the design tokens from code
([`SalahPalette`](../Shared/WidgetUI/SalahPalette.swift)'s dark palette, with Increase
Contrast) rather than from the iPhone's color sets, and draws itself dark whatever the
watch's appearance.

Three pages, top to bottom, which the Digital Crown scrolls through:

- **Salah:** the next prayer on the time of day's sky, with its countdown, then the rest of
  its day. In the last 15 minutes the countdown turns gold inside a gold rim; for 15 minutes
  after a prayer begins, a Now badge and a count-up in the phase's color; after Isha,
  tomorrow's Fajr. While the adhan plays, the hero holds Stop.
- **Today:** the day's prayers and sunrise. The next is on the gold wash with its
  countdown, the one that just began on the phase's wash, and a time the day can't give says
  Not today. Rows show the time without its day period, as the watch face shows the clock.
  When a name and its time no longer fit on one line, at the larger text sizes, the time
  moves under the name.
- **Qibla:** the bearing from the place chosen on the iPhone, from SalahTimes'
  `Qibla.direction(from:)`. The watch's own location only corrects the compass to true north,
  so the page asks for When In Use access the first time it shows. With a reading within 15°
  the dial turns with the watch and says which way to turn; within 3° the ring turns gold and
  the watch taps the wrist. Without a compass, or without location access, the dial stays
  north up with the bearing in its centre.

With the wrist down the watch redraws once a minute, so the countdown drops its seconds.

## The complications

One widget, in the accessory families a watch face offers: circular (a gauge from the
previous prayer to the next around its glyph and countdown), rectangular (the glyph, name and
time, the live countdown and the progress, which the Smart Stack shows too), inline (one line,
"Asr in 2:16:00") and corner (the glyph, with a curved gauge and label). They calculate their own timeline with SalahWidgets'
`PrayerTimelineBuilder`, through the timeline the iPhone's widgets use
([`SalahWidgetTimeline`](../Shared/SalahWidgetTimeline.swift)); the countdown is a timer text
that WidgetKit advances itself. Each entry's relevance raises the Smart Stack's card from 15
minutes before a prayer until 15 minutes after it begins. A tap opens the first page.

## Verification boundaries

[`SalahWatchTests`](../SalahWatchTests) exercises the presentation, the Qibla states, the
receive path, the adhan plan, the runtime's composition, the complications' timeline,
relevance and each family's drawing, and the launch options, in a non-hosted bundle. The iOS
side's sends are tested in `SalahIOSTests`. [`SalahWatchUITests`](../SalahWatchUITests)
drives the installed app with taps, swipes and the Digital Crown: the pages, the adhan at
prayer time with Stop, Arabic, the larger text sizes, the compass states, and production
storage after a fresh install. The paired journey (CONTRIBUTING.md) sends the preferences
from an iPhone simulator to a paired watch simulator, and the Smart Stack journey runs the
complication on the watch face. A passing run doesn't establish the compass on a wrist,
sound through the watch's speaker, notifications forwarded from a real iPhone, or a
complication on a real face; the [watchOS validation notes](watchos-validation.md) list
those checks.
