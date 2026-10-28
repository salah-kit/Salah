# Apple Watch app journeys

These XCUITests drive the installed watch app as a person would: they tap, swipe and turn
the Digital Crown. Swipes move between the pages, as the crown does on a watch: XCUITest's
crown rotation scrolls a page but doesn't move between them. Their Debug launch options
stand in for the iPhone with a fixture of the preferences it would send, in a defaults suite
of their own; a relaunch keeps that suite and leaves the fixture out, so it has to read what
the watch kept. Screenshots are kept as result-bundle attachments.

- `WatchCoreJourneys` covers the next prayer with the rest of its day, the pages through
  Today to the Qibla, the adhan at prayer time with Stop, a muted watch, Arabic with Arabic
  digits, the larger text sizes, the Qibla without a compass and facing it, the preferences
  kept across a relaunch, and a watch with no preferences asking for the iPhone.
- `WatchProductionJourneys` launches without Debug launch options after a fresh
  installation, so the watch has no preferences and asks for the iPhone. Run it after a fresh
  installation.
- `WatchPairedJourneys` waits on the watch for preferences an iPhone app paired with it
  sent. It skips unless `SALAH_WATCH_PAIRED=1`; `scripts/paired-watch-journey.sh` sets it
  after setting Salah up on the paired iPhone simulator.
- `WatchSmartStackJourneys` adds Salah's widget to the Smart Stack through the watch face's
  own process, `com.apple.clockface`, which draws the stack, its editor and its gallery, and
  checks that the widget reads a prayer there and that a tap on it opens Salah's first page.
  It skips unless `SALAH_WATCH_SMART_STACK=1`; `scripts/smart-stack-journey.sh` sets it and
  reads the complications' log for the timeline the extension built.

Prayer arithmetic, the receive path, the adhan plan, the complications' timeline and the
Qibla's states are tested below the UI in `SalahWatchTests`; these journeys observe the
production construction and interaction boundaries instead.

## Launch options

Debug builds read these options only together with `-salah.watch.testSuite`; Release
builds ignore them.

| Option | Value |
|---|---|
| `-salah.watch.testSuite` | A name for the preferences suite, letters, digits, `-`, `_` and `.` |
| `-salah.watch.reset` | `true` empties the suite first |
| `-salah.watch.fixture` | `makkah`, `london` or `jakarta`: preferences as the iPhone would send them, with silent sounds. Without it the watch waits for the iPhone |
| `-salah.watch.language` | `en` or `ar` |
| `-salah.watch.mute` | `true` turns sounds off, as Mute on the iPhone does |
| `-salah.watch.now` | An ISO 8601 instant the clock starts at |
| `-salah.watch.frozen` | `true` keeps the clock at that instant |
| `-salah.watch.tab` | `now`, `today` or `qibla`: the page to open on |
| `-salah.watch.heading` | Degrees from true north, `calibrating`, `needsLocation` or `none`: the compass's reading |
