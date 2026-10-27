import AVFoundation
import CoreLocation
import Foundation
import MapKit
import MediaPlayer
import SalahAlerts
import SalahCore
import Testing
import UIKit

@Suite("iOS location, audio and alert boundaries")
struct ServicePolicyTests {
  @Test @MainActor
  func activityPublicationUsesTheServiceClockForImmediatePlaybackDuaAndStop() throws {
    let settings = try activitySettings()
    let prayer = try #require(
      settings.schedule.day(CivilDay(year: 2026, month: 6, day: 2)).day?[.asr])
    let uiDate = prayer.time.addingTimeInterval(-60)
    let staleScreen = SalahDisplay(date: uiDate, settings: settings, schedule: settings.schedule)
    let startedAt = uiDate.addingTimeInterval(0.75)
    let clock = ServiceActivityClock(startedAt.addingTimeInterval(0.01))
    var session: IOSPlaybackSession? = IOSPlaybackSession(
      playback: SalahPlayback(event: prayer, slot: .alert), startedAt: startedAt, duration: 0.2)
    // Reproduces the old construction: the last UI tick incorrectly rejects this new session.
    #expect(
      SalahActivityAttributes.ContentState(display: staleScreen, playbackSession: session)?.mode
        == .countdown)
    let coordinator = IOSActivityCoordinator(
      now: { clock.read() }, loadPlaybackSession: { session })
    let playing = try #require(coordinator.publication(settings: staleScreen.settings)?.state)
    #expect(playing.mode == .playing)
    #expect(playing.updatedAt == clock.read())
    #expect(playing.progressStart == startedAt)
    #expect(staleScreen.date == uiDate)
    session?.playback.isDua = true
    clock.set(startedAt.addingTimeInterval(0.05))
    let dua = try #require(coordinator.publication(settings: settings)?.state)
    #expect(dua.mode == .playing)
    #expect(dua.eyebrow == staleScreen.labels.playingDua)
    #expect(dua.updatedAt == clock.read())
    session = nil
    clock.set(startedAt.addingTimeInterval(0.1))
    #expect(coordinator.publication(settings: settings)?.state.mode == .countdown)
  }

  @Test @MainActor
  func activityPublicationStillRejectsFutureAndExpiredSessions() throws {
    let settings = try activitySettings()
    let prayer = try #require(
      settings.schedule.day(CivilDay(year: 2026, month: 6, day: 2)).day?[.asr])
    let startedAt = prayer.time.addingTimeInterval(-60)
    let clock = ServiceActivityClock(startedAt.addingTimeInterval(-0.01))
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: prayer, slot: .alert), startedAt: startedAt, duration: 0.2)
    let coordinator = IOSActivityCoordinator(
      now: { clock.read() }, loadPlaybackSession: { session })
    #expect(coordinator.publication(settings: settings)?.state.mode == .countdown)
    clock.set(startedAt)
    #expect(coordinator.publication(settings: settings)?.state.mode == .playing)
    clock.set(session.expiresAt)
    #expect(coordinator.publication(settings: settings)?.state.mode == .countdown)
  }

  @Test @MainActor
  func removingActivitySettingsInvokesTheActualRefreshCleanupPath() async {
    var ended = 0
    var sessionReads = 0
    let coordinator = IOSActivityCoordinator(
      loadPlaybackSession: {
        sessionReads += 1
        return nil
      },
      lifecycle: IOSActivityLifecycle(activities: { [] }, end: { _ in ended += 1 }))
    #expect(coordinator.publication(settings: nil) == nil)
    await coordinator.refresh(settings: nil, isForeground: false)
    #expect(ended == 1)
    #expect(sessionReads == 0)
  }

  private func activitySettings() throws -> SalahSettings {
    var preferences = IOSPreferences()
    preferences.language = .english
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262,
      timeZone: try #require(TimeZone(identifier: "Asia/Riyadh")), countryCode: "SA", name: "Makkah"
    )
    return try #require(preferences.mirror)
  }

  @Test func recordingAndDuaDurationsShareTheExternalStopLifetimeBoundaries() throws {
    let maximum = IOSPlaybackSession.maximumRecordingDuration
    #expect(
      try IOSAudioDurationPolicy.sessionDuration(recordingDuration: maximum, hasQueuedDua: false)
        == maximum)
    #expect(
      try IOSAudioDurationPolicy.sessionDuration(recordingDuration: maximum, hasQueuedDua: true)
        == IOSPlaybackSession.maximumDuration)
    #expect(throws: IOSAudioImportError.tooLong) {
      try IOSAudioDurationPolicy.sessionDuration(
        recordingDuration: maximum + 0.001, hasQueuedDua: false)
    }
    for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
      #expect(throws: IOSAudioImportError.empty) {
        try IOSAudioDurationPolicy.sessionDuration(recordingDuration: invalid, hasQueuedDua: true)
      }
    }
  }

  @Test func aNativeLongRecordingIsRejectedBeforeAnyOwnedMediaIsCopied() throws {
    let files = temporaryFiles()
    let directory = files.audioDirectory.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("long-recording.wav")
    try ServiceWaveFixture.writeSparseWave(
      to: source, duration: IOSPlaybackSession.maximumRecordingDuration + 1)
    let native = try AVAudioFile(forReading: source)
    #expect(
      Double(native.length) / native.processingFormat.sampleRate
        > IOSPlaybackSession.maximumRecordingDuration)
    #expect(throws: IOSAudioImportError.tooLong) { try files.importAudio(from: source) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: files.audioDirectory.path).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: files.soundsDirectory.path).isEmpty)
  }

  @Test func nowPlayingMetadataFollowsTheSelectedLanguageAndDuaPhase() {
    let english = Locale(identifier: "en")
    let arabic = Locale(identifier: "ar")
    #expect(IOSAudioMetadata(locale: english, isDua: false).title == "Adhan")
    #expect(IOSAudioMetadata(locale: english, isDua: false).artist == "Salah")
    #expect(IOSAudioMetadata(locale: arabic, isDua: false).title == "الأذان")
    #expect(IOSAudioMetadata(locale: arabic, isDua: false).artist == "صلاة")
    #expect(IOSAudioMetadata(locale: english, isDua: true).title == "Du’a after adhan")
    #expect(IOSAudioMetadata(locale: arabic, isDua: true).title == "الدعاء بعد الأذان")
    #expect(IOSAudioMetadata(locale: arabic, isDua: true).artist == "صلاة")
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func nativePlaybackPublishesLocalizedDuaAndIgnoresAnOldSpeechCompletion() async throws {
    let files = temporaryFiles()
    let directory = files.audioDirectory.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("short-adhan.caf")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_205))
    buffer.frameLength = buffer.frameCapacity
    if let samples = buffer.floatChannelData?[0] {
      for frame in 0..<Int(buffer.frameLength) { samples[frame] = 0 }
    }
    do {
      let writer = try AVAudioFile(forWriting: source, settings: format.settings)
      try writer.write(from: buffer)
    }
    let filename = try files.importAudio(from: source)
    let audio = IOSAudioService(files: files)
    defer { audio.stop() }
    let legacy = files.audioDirectory.appendingPathComponent("legacy-long.wav")
    try ServiceWaveFixture.writeSparseWave(
      to: legacy, duration: IOSPlaybackSession.maximumRecordingDuration + 1)
    audio.play(.custom(legacy.lastPathComponent), volume: 0, duaAfter: true)
    #expect(!audio.isPlaying && !audio.hasQueuedDua)
    #expect(audio.errorMessage == IOSAudioImportError.tooLong.errorDescription)
    audio.play(.none, volume: 0, duaAfter: true)
    #expect(!audio.isPlaying && !audio.hasQueuedDua)
    var phaseChanges = 0
    audio.onPlaybackChanged = { if $0 { phaseChanges += 1 } }
    audio.play(.custom(filename), volume: 0, duaAfter: true, locale: Locale(identifier: "ar"))
    #expect(audio.hasQueuedDua)
    for _ in 0..<100 where !audio.isPlayingDua && audio.isPlaying {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(audio.errorMessage == nil)
    #expect(audio.isPlaying && audio.isPlayingDua)
    #expect(!audio.hasQueuedDua)
    #expect(phaseChanges >= 2)
    #expect(
      MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String
        == "الدعاء بعد الأذان")
    #expect(
      MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtist] as? String
        == "صلاة")
    audio.speechSynthesizer(AVSpeechSynthesizer(), didFinish: AVSpeechUtterance(string: "old"))
    #expect(audio.isPlaying && audio.isPlayingDua)
    audio.stop()
    #expect(!audio.isPlaying && !audio.isPlayingDua && !audio.hasQueuedDua)
    #expect(audio.playbackStartedAt == nil && audio.expectedPlaybackEnd == nil)
    #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
  }

  @Test func compassNeverConfusesMagneticOrUnreliableHeadingWithTrueNorth() {
    #expect(IOSHeadingState.reading(trueHeading: -1, accuracy: 5) == .calibrating)
    #expect(IOSHeadingState.reading(trueHeading: 120, accuracy: -1) == .calibrating)
    #expect(IOSHeadingState.reading(trueHeading: 120, accuracy: 40) == .calibrating)
    #expect(IOSHeadingState.reading(trueHeading: 120, accuracy: 16) == .calibrating)
    #expect(IOSHeadingState.reading(trueHeading: .nan, accuracy: 5) == .calibrating)
    #expect(
      IOSHeadingState.reading(trueHeading: 369, accuracy: 5) == .ready(trueHeading: 9, accuracy: 5))
  }

  @Test func oldOrInvalidLocationFixesCannotBecomeCurrentLocation() {
    #expect(IOSLocationService.isUsableFix(accuracy: 1_500, age: 10))
    #expect(!IOSLocationService.isUsableFix(accuracy: -1, age: 0))
    #expect(!IOSLocationService.isUsableFix(accuracy: 30_000, age: 0))
    #expect(!IOSLocationService.isUsableFix(accuracy: 100, age: 121))
    #expect(!IOSLocationService.isUsableFix(accuracy: 100, age: -100))
    #expect(!IOSLocationService.isUsableFix(accuracy: 6_000, age: 900))
    #expect(IOSLocationService.isUsableFix(accuracy: 6_000, age: 900, reducedAccuracy: true))
    #expect(!IOSLocationService.isUsableFix(accuracy: 30_000, age: 0, reducedAccuracy: true))
    #expect(!IOSLocationService.isUsableFix(accuracy: 6_000, age: 1_201, reducedAccuracy: true))
    #expect(!IOSLocationService.isUsableFix(accuracy: .nan, age: 0, reducedAccuracy: true))
  }

  @Test @MainActor
  func anApproximateLocationFixIsResolvedInsteadOfIgnored() {
    let manager = ServiceLocationManager(accuracy: .reducedAccuracy)
    let service = IOSLocationService(manager: manager)
    defer { service.cancelLocation() }
    service.requestLocation()
    #expect(service.isLocating && manager.requests == 1)
    // About 6 km wide and 15 minutes old, as approximate location reports.
    service.locationManager(manager, didUpdateLocations: [locationFix(accuracy: 6_000, age: 900)])
    #expect(manager.stops == 1)
    #expect(service.errorMessage != couldNotLocate)
  }

  @Test(arguments: [false, true]) @MainActor
  func anUnusableSingleFixEndsTheRequestWithAnError(reducedAccuracy: Bool) {
    let manager = ServiceLocationManager(
      accuracy: reducedAccuracy ? .reducedAccuracy : .fullAccuracy)
    let service = IOSLocationService(manager: manager)
    defer { service.cancelLocation() }
    service.requestLocation()
    service.locationManager(
      manager, didUpdateLocations: [locationFix(accuracy: 30_000, age: 1_500)])
    #expect(!service.isLocating)
    #expect(service.errorMessage == couldNotLocate)
    #expect(service.location == nil)
  }

  /// The interface orientation Qibla passes before iOS 27 names the device edge at the top of
  /// the dial. The dial's own wiring needs an iOS 26 device (#65).
  @Test @MainActor
  func interfaceOrientationsNameTheDeviceEdgeAtTheTopOfTheDial() {
    #expect(IOSLocationService.headingOrientation(for: .portrait) == .portrait)
    #expect(IOSLocationService.headingOrientation(for: .portraitUpsideDown) == .portraitUpsideDown)
    #expect(IOSLocationService.headingOrientation(for: .landscapeLeft) == .landscapeRight)
    #expect(IOSLocationService.headingOrientation(for: .landscapeRight) == .landscapeLeft)
    #expect(IOSLocationService.headingOrientation(for: .unknown) == nil)
    // iOS 27 measures from the reference view's body instead.
    if #unavailable(iOS 27.0) {
      let manager = CLLocationManager()
      let service = IOSLocationService(manager: manager)
      service.setHeadingOrientation(.landscapeLeft)
      #expect(manager.headingOrientation == .landscapeRight)
      service.setHeadingOrientation(.unknown)
      #expect(manager.headingOrientation == .landscapeRight)
    }
  }

  private var couldNotLocate: String {
    "Could not get your location. Try again outdoors or choose a city."
  }

  private func locationFix(accuracy: Double, age: TimeInterval) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262), altitude: 0,
      horizontalAccuracy: accuracy, verticalAccuracy: -1,
      timestamp: Date(timeIntervalSinceNow: -age))
  }

  @Test func perSlotSoundsAndFridayOverrideRemainIndependentUnderMute() throws {
    let files = temporaryFiles()
    defer {
      try? FileManager.default.removeItem(at: files.audioDirectory.deletingLastPathComponent())
    }
    try files.prepareSoftTone()
    var preferences = IOSPreferences()
    preferences.notifications[.dhuhr] = IOSPrayerAlertSettings(
      atTime: true, sound: .system, beforeEnabled: true, beforeMinutes: 10,
      beforeSound: .none, afterEnabled: true, afterMinutes: 5, afterSound: .softTone)
    let friday = CivilDay(year: 2026, month: 10, day: 23)
    let subject = AlertSubject(scheduleDay: friday, prayer: .dhuhr, observance: .jumuah)
    let inherited = IOSNotificationPolicy.settings(
      for: subject, preferences: preferences, files: files)
    #expect(inherited.atTime)
    #expect(inherited.before == .seconds(600))
    #expect(inherited.after == .seconds(300))
    #expect(inherited.sound == .system)
    #expect(inherited.beforeSound == .none)
    #expect(inherited.afterSound == .named(IOSAudioFiles.softToneName))
    preferences.jumuahOverrideEnabled = true
    preferences.jumuahAlerts = IOSPrayerAlertSettings(
      atTime: false, beforeEnabled: true, beforeMinutes: 30)
    let override = IOSNotificationPolicy.settings(
      for: subject, preferences: preferences, files: files)
    #expect(!override.atTime)
    #expect(override.before == .seconds(1_800))
    preferences.muteSounds = true
    let muted = IOSNotificationPolicy.settings(for: subject, preferences: preferences, files: files)
    #expect(muted.before == override.before)
    #expect(muted.atTime == override.atTime)
    #expect(muted.sound == .none && muted.beforeSound == .none && muted.afterSound == .none)
  }

  @Test func offsetsAreValidatedAtTheServiceBoundaryAndSunriseStartsOff() {
    var preferences = IOSPreferences()
    preferences.notifications[.fajr] = IOSPrayerAlertSettings(
      beforeEnabled: true, beforeMinutes: 0, afterEnabled: true, afterMinutes: 5_000)
    let day = CivilDay(year: 2026, month: 10, day: 23)
    let files = temporaryFiles()
    let settings = IOSNotificationPolicy.settings(
      for: AlertSubject(scheduleDay: day, prayer: .fajr), preferences: preferences, files: files)
    #expect(settings.before == .seconds(60))
    #expect(settings.after == .seconds(7_200))
    #expect(
      !IOSNotificationPolicy.settings(
        for: AlertSubject(scheduleDay: day, prayer: .sunrise), preferences: preferences,
        files: files
      ).atTime)
  }

  @Test func importedAudioIsOwnedAndNotificationExcerptIsStrictlyUnderThirtySeconds() throws {
    let files = temporaryFiles()
    let folder = files.audioDirectory.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = folder.appendingPathComponent("chosen.caf")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050 * 31))
    buffer.frameLength = buffer.frameCapacity
    if let channel = buffer.floatChannelData?[0] {
      for frame in 0..<Int(buffer.frameLength) { channel[frame] = 0.05 }
    }
    do {
      let writer = try AVAudioFile(forWriting: source, settings: format.settings)
      try writer.write(from: buffer)
    }
    let filename = try files.importAudio(from: source)
    try FileManager.default.removeItem(at: source)
    let owned = try #require(files.playbackURL(for: .custom(filename)))
    let full = try AVAudioFile(forReading: owned)
    #expect(Double(full.length) / full.processingFormat.sampleRate == 31)
    let clip = try AVAudioFile(
      forReading: files.soundsDirectory.appendingPathComponent(
        IOSAudioFiles.clipName(for: filename)))
    let duration = Double(clip.length) / clip.processingFormat.sampleRate
    #expect(duration > 0 && duration < 30)
    #expect(duration <= IOSAudioFiles.notificationMaximumDuration)
    #expect(
      files.notificationSound(for: .custom(filename), muted: false)
        == .named(IOSAudioFiles.clipName(for: filename)))
    #expect(files.notificationSound(for: .custom(filename), muted: true) == .none)
  }

  @Test func packagedRegularAndFajrAdhanHaveRealFullAudioAndPlayableShortNotificationClips() throws
  {
    let packaged = IOSAudioFiles()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = IOSAudioFiles(
      audioDirectory: directory.appendingPathComponent("Audio"),
      soundsDirectory: directory.appendingPathComponent("Sounds"),
      resourcesDirectory: packaged.resourcesDirectory)
    try files.prepareSounds()
    for sound in [IOSSound.adhan, .fajrAdhan] {
      let source = try #require(files.playbackURL(for: sound))
      let full = try AVAudioFile(forReading: source)
      #expect(Double(full.length) / full.processingFormat.sampleRate > 60)
      let filename = try #require(IOSAudioFiles.builtInFilename(for: sound))
      let clipName = IOSAudioFiles.clipName(for: filename)
      let clip = try AVAudioFile(forReading: files.soundsDirectory.appendingPathComponent(clipName))
      let duration = Double(clip.length) / clip.processingFormat.sampleRate
      #expect(duration > 0 && duration < 30)
      #expect(files.notificationSound(for: sound, muted: false) == .named(clipName))
      #expect(files.notificationSound(for: sound, muted: true) == .none)
    }
  }

  @Test func missingOrEscapingCustomFileFallsBackWithoutEscapingTheAudioDirectory() {
    let files = temporaryFiles()
    #expect(files.playbackURL(for: .custom("../../outside.caf")) == nil)
    #expect(files.notificationSound(for: .custom("../outside.caf"), muted: false) == .system)
    #expect(files.notificationSound(for: .custom("missing.caf"), muted: false) == .system)
    #expect(IOSAudioService.clampedVolume(.nan) == 1)
    #expect(IOSAudioService.clampedVolume(-1) == 0)
    #expect(IOSAudioService.clampedVolume(2) == 1)
  }

  @Test @MainActor func cityWithoutAResolvedTimeZoneNeverBorrowsThePhonesZone() {
    let item = MKMapItem(location: CLLocation(latitude: 1.3521, longitude: 103.8198), address: nil)
    #expect(IOSMapLocation.resolve(item) == nil)
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func laterCitySearchWinsEvenWhenAnOldProviderIgnoresCancellation() async throws {
    let provider = ServiceCitySearcher()
    let service = IOSCitySearchService(searcher: provider, debounce: .zero)
    service.update(query: "London")
    await provider.started("London")
    service.update(query: "Cairo")
    await provider.started("Cairo")
    let cairo = city("Cairo", latitude: 30.0444, longitude: 31.2357, zone: "Africa/Cairo")
    provider.finish("Cairo", result: cairo)
    for _ in 0..<20 where service.isSearching { try await Task.sleep(for: .milliseconds(2)) }
    #expect(service.results == [cairo])
    provider.finish(
      "London", result: city("London", latitude: 51.5072, longitude: -0.1276, zone: "Europe/London")
    )
    try await Task.sleep(for: .milliseconds(5))
    #expect(service.results == [cairo])
    #expect(service.query == "Cairo")
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func leavingCitySearchInvalidatesAnInFlightSelection() async throws {
    let provider = ServiceCitySearcher()
    let service = IOSCitySearchService(searcher: provider, debounce: .zero)
    service.update(query: "London")
    await provider.started("London")
    service.cancel()
    provider.finish(
      "London", result: city("London", latitude: 51.5072, longitude: -0.1276, zone: "Europe/London")
    )
    try await Task.sleep(for: .milliseconds(5))
    #expect(service.results.isEmpty)
    #expect(service.query.isEmpty)
    #expect(!service.isSearching)
    #expect(service.errorMessage == nil)
  }

  private func city(_ name: String, latitude: Double, longitude: Double, zone: String)
    -> IOSCityResult
  {
    IOSCityResult(
      title: name, subtitle: "",
      location: PrayerLocation(
        latitude: latitude, longitude: longitude, timeZone: TimeZone(identifier: zone) ?? .gmt,
        name: name))
  }

  private func temporaryFiles() -> IOSAudioFiles {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return IOSAudioFiles(
      audioDirectory: directory.appendingPathComponent("Audio"),
      soundsDirectory: directory.appendingPathComponent("Sounds"))
  }
}

/// A service clock shared by a Sendable closure; the lock protects every access.
nonisolated private final class ServiceActivityClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date
  init(_ date: Date) { self.date = date }
  func read() -> Date { lock.withLock { date } }
  func set(_ value: Date) { lock.withLock { date = value } }
}

/// Reports granted access and records requests, so no prompt appears and no real fix arrives.
nonisolated private final class ServiceLocationManager: CLLocationManager {
  private let accuracy: CLAccuracyAuthorization
  private(set) var requests = 0
  private(set) var stops = 0

  init(accuracy: CLAccuracyAuthorization) {
    self.accuracy = accuracy
    super.init()
  }

  override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
  override var accuracyAuthorization: CLAccuracyAuthorization { accuracy }
  override func requestWhenInUseAuthorization() {}
  override func requestLocation() { requests += 1 }
  override func startUpdatingLocation() {}
  override func stopUpdatingLocation() { stops += 1 }
}

/// A valid sparse PCM file exercises native duration parsing without rendering long audio.
nonisolated private enum ServiceWaveFixture {
  static func writeSparseWave(to url: URL, duration: TimeInterval) throws {
    let sampleRate: UInt32 = 8_000
    let dataSize = UInt32(duration * Double(sampleRate)) * 2
    var header = Data()
    func integer<T: FixedWidthInteger>(_ value: T) {
      var littleEndian = value.littleEndian
      withUnsafeBytes(of: &littleEndian) { header.append(contentsOf: $0) }
    }
    header.append(contentsOf: "RIFF".utf8)
    integer(UInt32(36) + dataSize)
    header.append(contentsOf: "WAVEfmt ".utf8)
    integer(UInt32(16))
    integer(UInt16(1))
    integer(UInt16(1))
    integer(sampleRate)
    integer(sampleRate * 2)
    integer(UInt16(2))
    integer(UInt16(16))
    header.append(contentsOf: "data".utf8)
    integer(dataSize)
    try header.write(to: url)
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    try file.truncate(atOffset: UInt64(header.count) + UInt64(dataSize))
  }
}

/// Deliberately ignores cancellation, exercising the service's own stale-response boundary.
@MainActor private final class ServiceCitySearcher: IOSCitySearching {
  private var waiting: [String: CheckedContinuation<[IOSCityResult], any Error>] = [:]
  private var starts: [String: CheckedContinuation<Void, Never>] = [:]

  func search(_ query: String) async throws -> [IOSCityResult] {
    try await withCheckedThrowingContinuation { continuation in
      waiting[query] = continuation
      starts.removeValue(forKey: query)?.resume()
    }
  }
  func started(_ query: String) async {
    if waiting[query] != nil { return }
    await withCheckedContinuation { starts[query] = $0 }
  }
  func finish(_ query: String, result: IOSCityResult) {
    waiting.removeValue(forKey: query)?.resume(returning: [result])
  }
  func cancel() {}
}
