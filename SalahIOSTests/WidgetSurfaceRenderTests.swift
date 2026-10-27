import CoreGraphics
import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing
import UIKit

/// A native rendering harness for each fixed WidgetKit surface. These are visual artifacts,
/// not golden-pixel assertions: the live system font and OS rendering remain authoritative.
@Suite("iOS widget native rendering", .serialized)
@MainActor
struct WidgetSurfaceRenderTests {
  @Test func homeFamiliesRenderEveryLanguageAndAppearance() throws {
    AppResources.bundle = Bundle(for: WidgetResourceProbe.self)
    let directory = try evidenceDirectory()
    let cases: [(SalahWidgetSize, CGSize, String)] = [
      (.small, CGSize(width: 164.33, height: 164.33), "small"),
      (.medium, CGSize(width: 349.67, height: 164.33), "medium"),
      (.large, CGSize(width: 349.67, height: 365), "large"),
      (.extraLarge, CGSize(width: 715, height: 342), "extra-large"),
    ]
    for isArabic in [false, true] {
      for isDark in [false, true] {
        let display = try display(isArabic: isArabic)
        for (size, dimensions, name) in cases {
          let view = WidgetContentView(display: display, size: size)
            .background(WidgetSky(phase: display.phase))
            .environment(\.locale, display.locale)
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, isDark ? .dark : .light)
            .environment(\.salahTimerPause, display.date)
          try render(
            view, size: dimensions,
            to: directory.appendingPathComponent(
              "\(name)-\(isArabic ? "ar" : "en")-\(isDark ? "dark" : "light").png"))
        }
      }
    }
  }

  @Test func extraLargeRendersAtCompactIPadBoundsAndKeepsItsMarkersHollow() throws {
    let size = CGSize(width: 628, height: 300)
    for proposal in [size, CGSize(width: 715.735294, height: 341.911765)] {
      let metrics = ExtraLargeWidgetMetrics(size: proposal)
      #expect(metrics.leadingWidth.isFinite && metrics.contentHeight.isFinite)
      #expect(abs(metrics.leadingWidth + 220 + 1 + 40 + 40 - proposal.width) < 0.001)
      #expect(SunArcLayout.size.width * metrics.arcScale <= metrics.leadingWidth)
      #expect(metrics.separatorHeight + 36 <= proposal.height)
    }
    let center = CGPoint(x: 100, y: 100)
    let clip = SunArcStrokeClip(holes: [center], radius: 4.5)
      .path(in: CGRect(origin: .zero, size: size))
    #expect(!clip.contains(center, eoFill: true))
    #expect(clip.contains(CGPoint(x: 120, y: 100), eoFill: true))

    AppResources.bundle = Bundle(for: WidgetResourceProbe.self)
    let directory = try evidenceDirectory()
    for isArabic in [false, true] {
      let display = try display(isArabic: isArabic)
      let event = try #require(display.focus?.event)
      let playing = SalahDisplay(
        date: display.date, settings: display.settings, schedule: display.settings.schedule,
        playback: SalahPlayback(event: event, slot: .alert))
      let stop = try #require(WidgetStopContent(display: playing, size: .extraLarge))
      for (content, state) in [
        (AnyView(WidgetContentView(display: display, size: .extraLarge)), "schedule"),
        (AnyView(stop), "stop"),
      ] {
        try render(
          content.background(WidgetSky(phase: display.phase))
            .environment(\.locale, display.locale)
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, .light)
            .environment(\.salahTimerPause, display.date),
          size: size,
          to: directory.appendingPathComponent(
            "extra-large-ipad-628x300-\(state)-\(isArabic ? "ar" : "en").png"))
      }
    }
  }

  @Test func liveActivityAndRecoveryRenderTheirRealStates() throws {
    AppResources.bundle = Bundle(for: WidgetResourceProbe.self)
    let directory = try evidenceDirectory()
    for isArabic in [false, true] {
      let display = try display(isArabic: isArabic)
      let state = try #require(SalahActivityAttributes.ContentState(display: display))
      for isStale in [false, true] {
        try render(
          IOSActivityCard(state: state, isStale: isStale)
            .environment(\.salahTimerPause, display.date),
          size: CGSize(width: 374, height: 86),
          to: directory.appendingPathComponent(
            "activity-\(isStale ? "stale" : "countdown")-\(isArabic ? "ar" : "en").png"))
      }
      let dhuhr = try #require(display.listedDay?[.dhuhr])
      let startedDisplay = SalahDisplay(
        date: dhuhr.time.addingTimeInterval(4 * 60), settings: display.settings,
        schedule: display.settings.schedule)
      let started = try #require(SalahActivityAttributes.ContentState(display: startedDisplay))
      try render(
        IOSActivityCard(state: started)
          .environment(\.salahTimerPause, startedDisplay.date),
        size: CGSize(width: 374, height: 86),
        to: directory.appendingPathComponent("activity-now-\(isArabic ? "ar" : "en").png"))
      let maghrib = try #require(display.listedDay?[.maghrib])
      let playingAt = maghrib.time.addingTimeInterval(2 * 60)
      let playback = SalahPlayback(event: maghrib, slot: .alert)
      let session = IOSPlaybackSession(
        playback: playback, startedAt: playingAt, duration: 90)
      let playingDisplay = SalahDisplay(
        date: playingAt, settings: display.settings, schedule: display.settings.schedule,
        playback: playback)
      let playing = try #require(
        SalahActivityAttributes.ContentState(display: playingDisplay, playbackSession: session))
      try render(
        IOSActivityCard(state: playing)
          .environment(\.salahTimerPause, playingAt),
        size: CGSize(width: 374, height: 86),
        to: directory.appendingPathComponent("activity-playing-\(isArabic ? "ar" : "en").png"))
      for (size, dimensions, name) in [
        (SalahWidgetSize.small, CGSize(width: 164.33, height: 164.33), "small"),
        (.large, CGSize(width: 349.67, height: 365), "large"),
      ] {
        let stop = try #require(WidgetStopContent(display: playingDisplay, size: size))
        try render(
          stop.background(WidgetSky(phase: playingDisplay.phase))
            .environment(\.colorScheme, .light)
            .environment(\.locale, display.locale)
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight),
          size: dimensions,
          to: directory.appendingPathComponent("stop-\(name)-\(isArabic ? "ar" : "en").png"))
      }
      let message = IOSL10n.text(
        "Open Salah to set up prayer times", arabic: "افتح صلاة لإعداد أوقات الصلاة",
        locale: display.locale)
      try render(
        WidgetMessageContent(systemImage: "moon.stars", message: Text(verbatim: message))
          .background(WidgetSky(phase: .fajr))
          .environment(\.colorScheme, .light)
          .environment(\.locale, display.locale)
          .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight),
        size: CGSize(width: 164.33, height: 164.33),
        to: directory.appendingPathComponent("setup-\(isArabic ? "ar" : "en").png"))
    }
  }

  /// iPhone Duo's vertical Dynamic Island, like the island on iPhone in landscape, limits compact
  /// and minimal presentations to a 28-point circle. Paused and stale rings are drawn here; the
  /// live ring is the system's timer progress view, which only a Live Activity host draws.
  @Test func limitedWidthIslandFitsItsCircleAndLeavesTheTrailingViewEmpty() throws {
    AppResources.bundle = Bundle(for: WidgetResourceProbe.self)
    let directory = try evidenceDirectory()
    let display = try display(isArabic: false)
    let countdown = try #require(SalahActivityAttributes.ContentState(display: display))
    let dhuhr = try #require(display.listedDay?[.dhuhr])
    let startedAt = dhuhr.time.addingTimeInterval(4 * 60)
    let justStarted = try #require(
      SalahActivityAttributes.ContentState(
        display: SalahDisplay(
          date: startedAt, settings: display.settings, schedule: display.settings.schedule)))
    let maghrib = try #require(display.listedDay?[.maghrib])
    let playingAt = maghrib.time.addingTimeInterval(2 * 60)
    let playback = SalahPlayback(event: maghrib, slot: .alert)
    let playing = try #require(
      SalahActivityAttributes.ContentState(
        display: SalahDisplay(
          date: playingAt, settings: display.settings, schedule: display.settings.schedule,
          playback: playback),
        playbackSession: IOSPlaybackSession(
          playback: playback, startedAt: playingAt, duration: 90)))
    #expect(
      [countdown.mode, justStarted.mode, playing.mode] == [.countdown, .justStarted, .playing])
    for (state, date, name) in [
      (countdown, display.date, "countdown"), (justStarted, startedAt, "now"),
      (playing, playingAt, "playing"),
    ] {
      for isStale in [false, true] {
        let renderer = ImageRenderer(
          content: IOSActivityLimitedIsland(state: state, isStale: isStale)
            .environment(\.salahTimerPause, date))
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        #expect(image.size.width <= 28.5 && image.size.height <= 28.5, "\(name): \(image.size)")
        #expect(drawnPixels(in: image) > 100, "\(name) must draw its ring and symbol")
        #expect(
          drawnPixels(in: image, outsideCircle: 28) == 0, "\(name) must stay inside its circle")
        let data = try #require(image.pngData())
        try data.write(
          to: directory.appendingPathComponent(
            "island-limited-\(name)\(isStale ? "-stale" : "").png"),
          options: .atomic)
      }
      // With limited width only the leading view shows; the trailing one draws nothing.
      let trailing = ImageRenderer(
        content: IOSActivityCompactTrailing(state: state, isStale: false, isLimitedInWidth: true)
          .environment(\.salahTimerPause, date))
      #expect(trailing.uiImage == nil || trailing.uiImage?.size == .zero)
    }
  }

  @Test func fridayUsesTheActualJumuahSymbolOnWidgetsAndActivities() throws {
    AppResources.bundle = Bundle(for: WidgetResourceProbe.self)
    #expect(UIImage(named: "salah.jumuah", in: AppResources.bundle, compatibleWith: nil) != nil)
    #expect(PrayerGlyph(kind: .dhuhr, observance: .jumuah).assetName == "salah.jumuah")
    #expect(PrayerGlyph(kind: .dhuhr).assetName == "salah.dhuhr")
    let directory = try evidenceDirectory()
    for isArabic in [false, true] {
      let base = try display(isArabic: isArabic)
      let friday = CivilDay(year: 2026, month: 6, day: 5)
      let event = try #require(base.settings.schedule.day(friday).day?[.dhuhr])
      #expect(event.observance == .jumuah)
      let now = event.time.addingTimeInterval(-10 * 60)
      let display = SalahDisplay(
        date: now, settings: base.settings, schedule: base.settings.schedule)
      let state = try #require(SalahActivityAttributes.ContentState(display: display))
      #expect(state.prayerObservance == .jumuah)
      let locale = display.locale
      let direction: LayoutDirection = isArabic ? .rightToLeft : .leftToRight
      try render(
        WidgetContentView(display: display, size: .small)
          .background(WidgetSky(phase: display.phase))
          .environment(\.locale, locale)
          .environment(\.layoutDirection, direction)
          .environment(\.colorScheme, .light)
          .environment(\.salahTimerPause, now),
        size: CGSize(width: 164.33, height: 164.33),
        to: directory.appendingPathComponent("friday-small-\(isArabic ? "ar" : "en").png"))
      try render(
        IOSActivityCard(state: state).environment(\.salahTimerPause, now),
        size: CGSize(width: 374, height: 86),
        to: directory.appendingPathComponent("friday-activity-\(isArabic ? "ar" : "en").png"))
      try render(
        IOSAccessoryCopy.inlineText(
          display: display, pause: now, bundle: AppResources.bundle
        )
        .foregroundStyle(.white)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, direction)
        .background(.black),
        size: CGSize(width: 250, height: 24),
        to: directory.appendingPathComponent("friday-inline-\(isArabic ? "ar" : "en").png"))
    }
  }

  @Test func accessoryCountdownCopyUsesTheSelectedLanguageInsteadOfDirection() {
    let bundle = Bundle(for: WidgetResourceProbe.self)
    for (language, expected) in [("ar", "بعد"), ("fa", "تا"), ("ur", "میں"), ("fr", "dans")] {
      #expect(
        IOSAccessoryCopy.countdownPrefix(locale: Locale(identifier: language), bundle: bundle)
          == expected)
    }
  }

  /// Paused at two moments, the spoken label reads two durations, so it carries one. The
  /// extension never sets `salahTimerPause`, so unpaused it takes the live timer, which reads the
  /// clock rather than its entry: two entries four minutes apart, both past the fixture's
  /// interval, read the same, where a snapshot of each entry's own moment would differ.
  @Test func accessorySpokenLabelsCarryADurationAndReadTheClockRatherThanTheEntry() throws {
    #expect(EnvironmentValues().salahTimerPause == nil)
    for isArabic in [false, true] {
      let base = try display(isArabic: isArabic)
      let dhuhr = try #require(base.listedDay?[.dhuhr])
      let countUp = SalahDisplay(
        date: dhuhr.time.addingTimeInterval(60), settings: base.settings,
        schedule: base.settings.schedule)
      for display in [base, countUp] {
        let paused = IOSAccessoryCopy.accessibilityLabel(display: display, pause: display.date)
        let pausedLater = IOSAccessoryCopy.accessibilityLabel(
          display: display, pause: display.date.addingTimeInterval(4 * 60))
        #expect(
          try accessoryAccessibilityImage(paused, display: display)
            != accessoryAccessibilityImage(pausedLater, display: display),
          "The paused spoken label must carry its duration, for countdowns and count-ups in either direction"
        )
        let entry = laterEntry(after: display)
        let first = IOSAccessoryCopy.accessibilityLabel(display: display)
        let later = IOSAccessoryCopy.accessibilityLabel(display: entry)
        #expect(
          try accessoryAccessibilityImage(first, display: display)
            == accessoryAccessibilityImage(later, display: entry),
          "The spoken timer must read the clock, not its timeline entry, for countdowns and count-ups in either direction"
        )
      }
    }
  }

  @Test func inlineAndRectangularAccessoriesKeepTheirClockInOneTextValue() throws {
    let bundle = Bundle(for: WidgetResourceProbe.self)
    AppResources.bundle = bundle
    let directory = try evidenceDirectory()
    for isArabic in [false, true] {
      let base = try display(isArabic: isArabic)
      let dhuhr = try #require(base.listedDay?[.dhuhr])
      let countUp = SalahDisplay(
        date: dhuhr.time.addingTimeInterval(60), settings: base.settings,
        schedule: base.settings.schedule)
      for display in [base, countUp] {
        let focus = try #require(display.focus)
        let later = display.date.addingTimeInterval(4 * 60)
        // Text is the inline host's extraction boundary. A stack of separate name and
        // timer views renders in ImageRenderer but loses the timer on the Lock Screen.
        let inline: Text = IOSAccessoryCopy.inlineText(
          display: display, pause: display.date, bundle: bundle)
        let laterInline: Text = IOSAccessoryCopy.inlineText(
          display: display, pause: later, bundle: bundle)
        let clock: Text = IOSAccessoryCopy.clockText(
          display: display, focus: focus, pause: display.date, bundle: bundle)
        let laterClock: Text = IOSAccessoryCopy.clockText(
          display: display, focus: focus, pause: later, bundle: bundle)
        for (first, advanced) in [(inline, laterInline), (clock, laterClock)] {
          #expect(
            try accessoryAccessibilityImage(first, display: display)
              != accessoryAccessibilityImage(advanced, display: display),
            "The single extracted text value must contain the countdown or elapsed clock")
        }
        // The extension's own path, unpaused: the live clock in that value reads the same
        // from an entry four minutes later, where a snapshot of each entry would differ.
        let entry = laterEntry(after: display)
        let entryFocus = try #require(entry.focus)
        for (live, laterLive) in [
          (
            IOSAccessoryCopy.inlineText(display: display, bundle: bundle),
            IOSAccessoryCopy.inlineText(display: entry, bundle: bundle)
          ),
          (
            IOSAccessoryCopy.clockText(display: display, focus: focus, bundle: bundle),
            IOSAccessoryCopy.clockText(display: entry, focus: entryFocus, bundle: bundle)
          ),
        ] {
          #expect(
            try accessoryAccessibilityImage(live, display: display)
              == accessoryAccessibilityImage(laterLive, display: entry),
            "The extracted text value must hold the live clock, not its timeline entry's reading")
        }
        let state = focus.isCountUp ? "elapsed" : "countdown"
        let language = isArabic ? "ar" : "en"
        for (text, name, size, font) in [
          (inline, "inline", CGSize(width: 250, height: 24), Font.body),
          (clock, "rectangular-clock", CGSize(width: 148, height: 26), .title3.weight(.medium)),
        ] {
          try render(
            text.font(font).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
              .foregroundStyle(.white)
              .environment(\.locale, display.locale)
              .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
              .background(.black),
            size: size,
            to: directory.appendingPathComponent("accessory-\(name)-\(state)-\(language).png"))
        }
      }
    }
  }

  /// The timeline entry four minutes after `display`, with the same focus.
  private func laterEntry(after display: SalahDisplay) -> SalahDisplay {
    let entry = SalahDisplay(
      date: display.date.addingTimeInterval(4 * 60), settings: display.settings,
      schedule: display.settings.schedule)
    #expect(entry.focus == display.focus)
    return entry
  }

  private func accessoryAccessibilityImage(_ text: Text, display: SalahDisplay) throws -> Data {
    let renderer = ImageRenderer(
      content:
        text
        .font(.body)
        .foregroundStyle(.black)
        .environment(\.locale, display.locale)
        .environment(\.layoutDirection, display.isRightToLeft ? .rightToLeft : .leftToRight)
        .frame(width: 500, height: 70)
        .background(.white))
    renderer.scale = 1
    let image = try #require(renderer.uiImage)
    return try #require(image.pngData())
  }

  @Test func activityRegionEnvironmentOverridesTheDeviceLanguageAndTimeZone() throws {
    let display = try display(isArabic: false)
    let original = try #require(SalahActivityAttributes.ContentState(display: display))
    for language in ["ar", "fa", "ur", "fr"] {
      var state = original
      state.languageIdentifier = language
      state.timeZoneIdentifier = "Asia/Riyadh"
      var observed: (Locale, TimeZone, LayoutDirection, ColorScheme)?
      let probe = ActivityEnvironmentProbe { locale, zone, direction, scheme in
        observed = (locale, zone, direction, scheme)
      }
      .modifier(IOSActivityEnvironment(state: state))
      .environment(\.locale, Locale(identifier: "en_US"))
      .environment(\.timeZone, TimeZone(identifier: "Pacific/Honolulu") ?? .gmt)
      .environment(\.layoutDirection, .leftToRight)
      .environment(\.colorScheme, .light)
      let renderer = ImageRenderer(content: probe.frame(width: 1, height: 1))
      _ = try #require(renderer.uiImage)
      let values = try #require(observed)
      #expect(values.0.language.languageCode?.identifier == language)
      #expect(values.1.identifier == "Asia/Riyadh")
      #expect(values.2 == (language == "fr" ? .leftToRight : .rightToLeft))
      #expect(values.3 == .dark)
    }
  }

  private func display(isArabic: Bool) throws -> SalahDisplay {
    var preferences = IOSPreferences()
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: zone, countryCode: "SA",
      name: isArabic ? "مكة" : "Makkah")
    preferences.language = isArabic ? .arabic : .english
    let settings = try #require(preferences.mirror)
    let now = CivilDay(year: 2026, month: 6, day: 2).start(in: zone)
      .addingTimeInterval(13 * 3_600 + 19 * 60)
    return SalahDisplay(date: now, settings: settings, schedule: settings.schedule)
  }

  private func evidenceDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SalahIOS-widget-rendering", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /// Counts pixels with any coverage; with a diameter in points, only those outside the
  /// centered circle, allowing one pixel of antialiasing.
  private func drawnPixels(in image: UIImage, outsideCircle diameter: CGFloat? = nil) -> Int {
    guard let cgImage = image.cgImage else { return 0 }
    let width = cgImage.width
    let height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return 0 }
    let radius = diameter.map { $0 / 2 * image.scale + 1 } ?? .infinity
    var count = 0
    for y in 0..<height {
      for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 0 {
        let dx = CGFloat(x) + 0.5 - CGFloat(width) / 2
        let dy = CGFloat(y) + 0.5 - CGFloat(height) / 2
        if (dx * dx + dy * dy).squareRoot() > radius || diameter == nil { count += 1 }
      }
    }
    return count
  }

  /// Native bridge views unsupported offscreen draw a bright yellow warning stripe.
  /// This narrowly catches that defect without asserting every font or antialiased pixel.
  private func unsupportedPlaceholderPixels(in image: UIImage) -> Int {
    guard let image = image.cgImage else { return 0 }
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    return bytes.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return 0 }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      let pixels = buffer.bindMemory(to: UInt8.self)
      var count = 0
      for offset in stride(from: 0, to: pixels.count, by: 4) {
        if pixels[offset] > 250 && pixels[offset + 1] > 190 && pixels[offset + 1] < 220
          && pixels[offset + 2] < 30
        {
          count += 1
        }
      }
      return count
    }
  }

  private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = 2
    let image = try #require(renderer.uiImage)
    #expect(abs(image.size.width - size.width) < 0.5)
    #expect(abs(image.size.height - size.height) < 0.5)
    let data = try #require(image.pngData())
    #expect(data.count > 1_000, "The surface must draw content instead of a blank rectangle")
    #expect(
      unsupportedPlaceholderPixels(in: image) == 0,
      "ImageRenderer cannot draw this native view; the surface contains its yellow warning placeholder"
    )
    try data.write(to: url, options: .atomic)
    print("Widget surface evidence: \(url.path)")
  }
}

private final class WidgetResourceProbe: NSObject {}

@MainActor
private struct ActivityEnvironmentProbe: View {
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
  @Environment(\.layoutDirection) private var direction
  @Environment(\.colorScheme) private var colorScheme
  let read: @MainActor (Locale, TimeZone, LayoutDirection, ColorScheme) -> Void

  var body: some View {
    let _ = read(locale, timeZone, direction, colorScheme)
    Color.clear
  }
}
