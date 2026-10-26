# Apple TV app journeys

These XCUITests drive the installed app with the Siri Remote, as a person would: they move
focus and press, and never tap. Their Debug launch options isolate durable preferences
without replacing city search, calculation, permission requests or navigation. Every
launch uses its own defaults suite; a relaunch keeps that suite, so it has to read the
saved changes. Screenshots are kept as result-bundle attachments.

- `TVCoreJourneys` covers Today and where focus lands, a prayer row opening its sound, the
  room display with Back and with Home and back, the adhan at prayer time with Stop, with
  Play/Pause and Back over the room display, over a prayer's sound page and over a browsed
  week, the week turning at both ends and coming back to the current week, About scrolling
  to its end, persistence across relaunch, Arabic right to left, and Larger Text with
  Today's hero and source line in reach.
- `TVTopShelfJourneys` goes to the Home Screen, checks the three banners the Top Shelf
  extension drew from the app's mirror, and opens the room display from its banner.
- `TVPermissionJourneys` answers the real location alert with Allow Once and with Don't
  Allow, after which focus is back on Use Location. Each journey resets Salah's location
  permission first. Allowing needs a simulated
  location, for example latitude `21.4225`, longitude `39.8262`.
- `TVProductionJourneys` sets up and checks persistence without Debug launch options. Run
  it after a fresh installation.

The city journeys use Apple Maps search and the location journey Apple's geocoding, so they
need a network connection. Prayer arithmetic, the adhan plan, the Top Shelf images and the
reload rule are tested below the UI in `SalahTVTests`; these journeys observe the
production construction and interaction boundaries instead.

## Launch options

Debug builds read these options only together with `-salah.tv.testSuite`; Release builds
ignore them.

| Option | Value |
|---|---|
| `-salah.tv.testSuite` | A name for the preferences suite, letters, digits, `-`, `_` and `.` |
| `-salah.tv.reset` | `true` empties the suite first |
| `-salah.tv.fixture` | `makkah`, `london` or `jakarta`: a city to start with |
| `-salah.tv.language` | `en` or `ar` |
| `-salah.tv.appearance` | `light` or `dark` |
| `-salah.tv.skipOnboarding` | `true` starts on the tabs |
| `-salah.tv.now` | An ISO 8601 instant the app's clock starts from |
| `-salah.tv.frozen` | `true` keeps the clock at that instant |
| `-salah.tv.route` | `today`, `week`, `settings` or `room` |
