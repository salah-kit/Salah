import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing

/// Renders every widget state, `WidgetPreviewContainer` scenario, widget family and
/// the menu-bar dropdown, in English, Arabic and French, light and dark, and checks
/// them against `Baselines/` (see its README for the inputs and the record command).
@Suite("Visual baselines")
struct VisualBaselineTests {
  init() { TestEnvironment.configure() }

  static let mode = BaselineMode.current

  /// Native normal desktop frames measured on Mac14,10, macOS 27.0.1 (#28).
  /// Check the rendered container, independently of the reference-size constants.
  @Test func widgetPreviewsMatchMeasuredNormalDesktopFrames() throws {
    let references: [(family: Baseline.Family, width: Int, height: Int)] = [
      (.small, 164, 164), (.medium, 344, 164), (.large, 344, 344),
    ]
    for language in [Baseline.Language.en, .ar] {
      for reference in references {
        let baseline = Baseline(
          surface: .widget, state: SpecState.idle.rawValue, family: reference.family,
          language: language, appearance: .dark)
        let png = try AppLanguageScope.with(BaselinePipeline.appLanguage(language)) {
          try BaselineRenderer.stablePNG { try BaselinePipeline.view(for: baseline) }
        }
        let pixels = try #require(PixelComparison.rgba(png))
        #expect(pixels.width == reference.width * BaselineRenderer.scale)
        #expect(pixels.height == reference.height * BaselineRenderer.scale)
      }
    }
  }

  /// Each run renders its own share (`Baseline.processLanguages`): the main run
  /// everything but the Arabic menu dropdown, the `-testLanguage ar` run only that.
  @Test(
    .enabled(if: BaselineMode.current.renders, BaselineMode.current.skipReason),
    .enabled(if: !BaselineCatalog.forThisProcess.isEmpty, BaselineCatalog.processSkipReason),
    arguments: BaselineCatalog.forThisProcess)
  func baseline(_ baseline: Baseline) throws {
    // Rendering settles on one image: no live clock, animation or timer leaks into
    // it (`stablePNG` throws if four renders in a row never agree).
    let png = try AppLanguageScope.with(BaselinePipeline.appLanguage(baseline.language)) {
      try BaselineRenderer.stablePNG { try BaselinePipeline.view(for: baseline) }
    }

    let url = BaselineStore.directory.appending(path: baseline.path)
    switch Self.mode {
    case .record:
      // Keep a PNG the render still matches, so noise never churns the history.
      if let recorded = try? Data(contentsOf: url),
        PixelComparison.compare(png, to: recorded)?.matches == true
      {
        return
      }
      try BaselineStore.write(png, to: url)
    case .compare:
      let failure = BaselineStore.failuresDirectory.appending(path: baseline.path)
      let checked = try PixelComparison.check(
        png, against: try? Data(contentsOf: url), failure: failure)
      let result = try #require(checked, "\(baseline.path): no recorded PNG to compare with")
      #expect(result.matches, "\(baseline.path): \(result)")
    case .skip:
      break
    }
  }

  /// `README.md` and `index.json` match the catalog; the main run's record mode
  /// rewrites them and `environment.json`.
  @Test func indexMatchesTheCatalog() throws {
    let readme = BaselineStore.directory.appending(path: "README.md")
    let index = BaselineStore.directory.appending(path: "index.json")
    if Self.mode == .record {
      guard Locale.preferredLanguages == Baseline.mainProcessLanguages else { return }
      try BaselineStore.write(Data(BaselineIndex.readme().utf8), to: readme)
      try BaselineStore.write(BaselineIndex.json(), to: index)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try BaselineStore.write(
        encoder.encode(BaselineEnvironment.current) + Data("\n".utf8), to: BaselineEnvironment.url)
      return
    }
    try #require(FileManager.default.fileExists(atPath: readme.path), "no baselines recorded yet")
    #expect(try String(contentsOf: readme, encoding: .utf8) == BaselineIndex.readme())
    #expect(try Data(contentsOf: index) == BaselineIndex.json())
  }

  /// Every PNG under `Baselines/` is in the catalog, so stale images can't linger.
  @Test(.enabled(if: BaselineMode.current == .compare, BaselineMode.current.skipReason))
  func noOrphanedImages() throws {
    let expected = Set(BaselineCatalog.all.map(\.path))
    let enumerator = FileManager.default.enumerator(
      at: BaselineStore.directory, includingPropertiesForKeys: nil)
    var found: Set<String> = []
    while let url = enumerator?.nextObject() as? URL {
      guard url.pathExtension == "png" else { continue }
      found.insert(url.path.replacingOccurrences(of: BaselineStore.directory.path + "/", with: ""))
    }
    #expect(found == expected)
  }

  /// The setup face has no settings to take a language from: the extension shows it in
  /// the device's language, so it's the same whatever language the app is set to,
  /// although the extension's catalog has the message in Arabic and French. This renders
  /// the tests' copy of the extension shell's setup branch (`WidgetShellMessage`), as the
  /// baselines do: it pins the face and its text, not the extension's own branch.
  @Test func setupFaceFollowsTheDeviceNotTheApp() throws {
    let messages = try ["en", "ar", "fr"].map {
      try ExtensionCatalog.string("widget.openToSetUp", localeIdentifier: $0)
    }
    #expect(Set(messages).count == 3)

    func png(_ language: Baseline.Language) throws -> Data {
      let baseline = Baseline(
        surface: .widget, state: SpecState.setupNeeded.rawValue, family: .medium,
        language: language, appearance: .light)
      return try AppLanguageScope.with(BaselinePipeline.appLanguage(language)) {
        try BaselineRenderer.stablePNG { try BaselinePipeline.view(for: baseline) }
      }
    }
    // Compared like the baselines: a face's first render in a process can settle a
    // few pixels apart from later ones.
    let english = try png(.en)
    for language in [Baseline.Language.ar, .fr] {
      let result = try #require(PixelComparison.compare(png(language), to: english))
      #expect(result.matches, "\(language): \(result)")
    }
  }

  /// Caption-size text, light on dark, as the faces show it.
  static func textPNG(_ text: String) throws -> Data {
    try BaselineRenderer.stablePNG {
      Text(verbatim: text).font(.caption2).foregroundStyle(.white).padding(4)
        .background(.black)
    }
  }

  /// The tolerance absorbs antialiasing jitter, not a changed mark: a diacritic alone
  /// changes about ten pixels at caption size, each by far more than jitter does.
  @Test func aDiacriticAloneIsADifference() throws {
    for (marked, plain) in [("تنبيه مُفعّل", "تنبيه مفعّل"), ("Ishā", "Isha")] {
      let markedPNG = try Self.textPNG(marked)
      let markedAgain = try Self.textPNG(marked)
      let plainPNG = try Self.textPNG(plain)
      let result = try #require(PixelComparison.compare(markedPNG, to: plainPNG))
      #expect(!result.matches, "\(marked) vs \(plain): \(result)")
      #expect(PixelComparison.compare(markedPNG, to: markedAgain)?.matches == true)
    }
  }

  /// A failed comparison leaves the render in the failures folder, and so does a
  /// missing baseline; once the face matches again, a render left by an earlier run
  /// is removed.
  @Test func failedRendersStayOnlyWhileTheyDiffer() throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "SalahTests-failures-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let failure = folder.appending(path: "widget/face.png")
    let marked = try Self.textPNG("Ishā")
    let plain = try Self.textPNG("Isha")

    let differing = try PixelComparison.check(marked, against: plain, failure: failure)
    #expect(differing?.matches == false)
    #expect(FileManager.default.fileExists(atPath: failure.path))
    let matching = try PixelComparison.check(plain, against: plain, failure: failure)
    #expect(matching?.matches == true)
    #expect(!FileManager.default.fileExists(atPath: failure.path))
    let missing = try PixelComparison.check(plain, against: nil, failure: failure)
    #expect(missing == nil)
    #expect(FileManager.default.fileExists(atPath: failure.path))
  }

  @Test func catalogCoversEveryStateFamilyLanguageAndAppearance() {
    let all = BaselineCatalog.all
    #expect(Set(all.map(\.path)).count == all.count)
    #expect(all.filter { $0.surface == .widget }.count == SpecState.allCases.count * 3 * 3 * 2)
    #expect(
      all.filter { $0.surface == .menu }.count == SpecState.allCases.filter(\.onMenu).count * 3 * 2)
    #expect(
      all.filter { $0.surface == .preview }.count == PreviewScenario.allCases.count * 3 * 3 * 2)
    #expect(all.filter { $0.surface == .phase }.count == SalahPhase.allCases.count * 3 * 2)
    // Only the Arabic menu dropdown renders in the Arabic run.
    #expect(
      all.filter { $0.processLanguages == ["ar"] }
        == all.filter { $0.surface == .menu && $0.language == .ar })
    #expect(
      Set(all.map(\.processLanguages)) == [Baseline.mainProcessLanguages, ["ar"]])
  }

  /// The fixture moments land in the states they name.
  @Test func specStateMomentsShowTheirStates() throws {
    func display(_ state: SpecState) -> SalahDisplay {
      BaselinePipeline.display(for: state, language: .en)
    }
    func focus(_ state: SpecState) -> SalahDisplay.Focus? { display(state).focus }
    #expect(focus(.idle) == .countdown(Fixture.event(.asr)))
    #expect(display(.imminent).tone == .imminent)
    #expect(focus(.countUp) == .countUp(Fixture.event(.dhuhr)))
    #expect(display(.countUpSilent).backgroundTone == .silent)
    let overlap = display(.countUpImminent)
    #expect(overlap.focus == .countUp(Fixture.event(.maghrib, ishaAdjustment: -78)))
    #expect(overlap.tone == .imminent)
    #expect(focus(.endOfDay) == .countdown(Fixture.event(.fajr, dayOffset: 1)))
    #expect(display(.endOfDay).focusIsTomorrow)
    #expect(display(.playingAdhan).playback?.slot == .alert)
    #expect(display(.playingPreReminder).playback?.slot == .preReminder)
    #expect(display(.playingPostReminder).playback?.slot == .postReminder)
    #expect(display(.silent).settings.silentMode)
    // The stale face is the expired entry: the moment is past the fixture day.
    #expect(
      BaselinePipeline.moment(for: .stale) > Fixture.civilDay(offset: 1).start(in: Fixture.timeZone)
    )
    // No state sits within a minute of a prayer, where the views switch to the
    // system's live timer text, which reads the real clock.
    for state in SpecState.allCases where state != .stale && state != .setupNeeded {
      let moment = BaselinePipeline.moment(for: state)
      let times =
        Fixture.day(ishaAdjustment: state.ishaAdjustment).events.map(\.time)
        + [Fixture.time(.fajr, dayOffset: 1)]
      #expect(times.allSatisfy { abs($0.timeIntervalSince(moment)) > 60 }, "\(state)")
    }
  }
}
