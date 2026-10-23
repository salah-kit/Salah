import AVFoundation
import Foundation
import SalahAlerts

nonisolated enum IOSAudioImportError: Error, LocalizedError, Equatable, Sendable {
  case unreadable, empty, tooLarge, tooLong, unsupportedChannels

  var errorDescription: String? {
    switch self {
    case .unreadable: "This audio file could not be opened. Choose another file."
    case .empty: "This audio file has no playable audio."
    case .tooLarge: "Choose an audio file smaller than 100 MB."
    case .tooLong: "Choose an audio file no longer than 30 minutes."
    case .unsupportedChannels: "Choose a mono or stereo audio file."
    }
  }
}

/// Original media and its optional du'a share the same lifetime contract as external Stop.
nonisolated enum IOSAudioDurationPolicy {
  static func sessionDuration(recordingDuration: TimeInterval, hasQueuedDua: Bool) throws
    -> TimeInterval
  {
    guard recordingDuration.isFinite, recordingDuration > 0 else { throw IOSAudioImportError.empty }
    guard recordingDuration <= IOSPlaybackSession.maximumRecordingDuration else {
      throw IOSAudioImportError.tooLong
    }
    return recordingDuration + (hasQueuedDua ? IOSPlaybackSession.duaMaximumDuration : 0)
  }
}

/// All imported media belongs to the app after selection; notification clips are PCM CAF.
nonisolated struct IOSAudioFiles: Sendable {
  let audioDirectory: URL
  let soundsDirectory: URL
  let resourcesDirectory: URL?
  static let softToneName = "salah-soft-tone.caf"
  static let notificationMaximumDuration = 29.0

  init(fileManager: FileManager = .default) {
    audioDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Audio", isDirectory: true)
    soundsDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Sounds", isDirectory: true)
    resourcesDirectory = Bundle(for: IOSAudioResourceAnchor.self).resourceURL
  }

  init(audioDirectory: URL, soundsDirectory: URL, resourcesDirectory: URL? = nil) {
    self.audioDirectory = audioDirectory
    self.soundsDirectory = soundsDirectory
    self.resourcesDirectory = resourcesDirectory
  }

  func prepareDirectories() throws {
    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
  }

  func prepareSounds() throws {
    try prepareSoftTone()
    for sound in [IOSSound.adhan, .fajrAdhan] {
      guard let source = playbackURL(for: sound), let name = Self.builtInFilename(for: sound) else {
        continue
      }
      let destination = soundsDirectory.appendingPathComponent(Self.clipName(for: name))
      if let saved = try? AVAudioFile(forReading: destination),
        Double(saved.length) / saved.processingFormat.sampleRate < 30, saved.length > 0
      {
        continue
      }
      try createNotificationClip(from: source, to: destination)
    }
  }

  /// A short synthesized chime has no third-party media or redistribution requirement.
  func prepareSoftTone() throws {
    try prepareDirectories()
    let destination = soundsDirectory.appendingPathComponent(Self.softToneName)
    if FileManager.default.fileExists(atPath: destination.path) { return }
    let sampleRate = 22_050.0
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * 1.4)),
      let samples = buffer.floatChannelData?[0]
    else { throw IOSAudioImportError.unreadable }
    buffer.frameLength = buffer.frameCapacity
    for frame in 0..<Int(buffer.frameLength) {
      let t = Double(frame) / sampleRate
      let attack = min(1, t / 0.025)
      let release = min(1, (1.4 - t) / 0.18)
      let envelope = attack * release * exp(-2.3 * t)
      samples[frame] = Float(
        0.26 * envelope * (sin(2 * .pi * 660 * t) + 0.35 * sin(2 * .pi * 990 * t)))
    }
    try writePCM(buffer, to: destination)
  }

  /// Copies the original, and creates a compatible <30-second notification excerpt.
  func importAudio(from source: URL) throws -> String {
    try prepareDirectories()
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    let resource = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard resource.isRegularFile == true else { throw IOSAudioImportError.unreadable }
    guard (resource.fileSize ?? 0) <= 100 * 1_024 * 1_024 else {
      throw IOSAudioImportError.tooLarge
    }
    let reader = try AVAudioFile(forReading: source)
    let format = reader.processingFormat
    guard reader.length > 0, format.sampleRate.isFinite, format.sampleRate > 0 else {
      throw IOSAudioImportError.empty
    }
    guard (1...2).contains(format.channelCount) else {
      throw IOSAudioImportError.unsupportedChannels
    }
    _ = try IOSAudioDurationPolicy.sessionDuration(
      recordingDuration: Double(reader.length) / format.sampleRate, hasQueuedDua: false)
    let suffix = source.pathExtension.lowercased()
    let safeSuffix =
      suffix.allSatisfy(\.isLetter) && !suffix.isEmpty && suffix.count < 8 ? suffix : "audio"
    let filename = "\(UUID().uuidString).\(safeSuffix)"
    let destination = audioDirectory.appendingPathComponent(filename)
    let clip = soundsDirectory.appendingPathComponent(Self.clipName(for: filename))
    do {
      try FileManager.default.copyItem(at: source, to: destination)
      try createNotificationClip(from: source, to: clip)
      return filename
    } catch {
      try? FileManager.default.removeItem(at: destination)
      try? FileManager.default.removeItem(at: clip)
      throw error
    }
  }

  func playbackURL(for sound: IOSSound) -> URL? {
    let url: URL
    switch sound {
    case .adhan, .fajrAdhan:
      guard let name = Self.builtInFilename(for: sound), let resourcesDirectory else { return nil }
      let direct = resourcesDirectory.appendingPathComponent(name)
      let nested = resourcesDirectory.appendingPathComponent("Audio").appendingPathComponent(name)
      url = FileManager.default.fileExists(atPath: direct.path) ? direct : nested
    case .softTone: url = soundsDirectory.appendingPathComponent(Self.softToneName)
    case .custom(let filename):
      guard Self.isManagedFilename(filename) else { return nil }
      url = audioDirectory.appendingPathComponent(filename)
    case .system, .none: return nil
    }
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  func notificationSound(for sound: IOSSound, muted: Bool) -> AlertSound {
    guard !muted else { return .none }
    switch sound {
    case .none: return .none
    case .system: return .system
    case .adhan, .fajrAdhan:
      guard let filename = Self.builtInFilename(for: sound) else { return .system }
      let name = Self.clipName(for: filename)
      return FileManager.default.fileExists(
        atPath: soundsDirectory.appendingPathComponent(name).path)
        ? .named(name) : .system
    case .softTone:
      return FileManager.default.fileExists(
        atPath: soundsDirectory.appendingPathComponent(Self.softToneName).path)
        ? .named(Self.softToneName) : .system
    case .custom(let filename):
      guard Self.isManagedFilename(filename) else { return .system }
      let name = Self.clipName(for: filename)
      return FileManager.default.fileExists(
        atPath: soundsDirectory.appendingPathComponent(name).path)
        ? .named(name) : .system
    }
  }

  static func isManagedFilename(_ name: String) -> Bool {
    !name.isEmpty && name == URL(fileURLWithPath: name).lastPathComponent && !name.contains("..")
      && !name.contains("/") && !name.contains("\\")
  }

  static func clipName(for filename: String) -> String {
    URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + "-notification.caf"
  }

  static func builtInFilename(for sound: IOSSound) -> String? {
    switch sound {
    case .adhan: "adhan-ahmed-khalaf.mp3"
    case .fajrAdhan: "fajr-adhan-ahmed-khalaf.mp3"
    default: nil
    }
  }

  private func createNotificationClip(from source: URL, to destination: URL) throws {
    let reader = try AVAudioFile(forReading: source)
    let format = reader.processingFormat
    guard reader.length > 0, format.sampleRate.isFinite, format.sampleRate > 0 else {
      throw IOSAudioImportError.empty
    }
    guard (1...2).contains(format.channelCount) else {
      throw IOSAudioImportError.unsupportedChannels
    }
    let frames = AVAudioFrameCount(
      min(
        reader.length, AVAudioFramePosition(format.sampleRate * Self.notificationMaximumDuration)))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
      throw IOSAudioImportError.unreadable
    }
    try reader.read(into: buffer, frameCount: frames)
    guard buffer.frameLength > 0 else { throw IOSAudioImportError.empty }
    try writePCM(buffer, to: destination)
    let saved = try AVAudioFile(forReading: destination)
    let duration = Double(saved.length) / saved.processingFormat.sampleRate
    guard duration > 0, duration < 30 else { throw IOSAudioImportError.unreadable }
  }

  private func writePCM(_ buffer: AVAudioPCMBuffer, to destination: URL) throws {
    let format = buffer.format
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let writer = try AVAudioFile(
      forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32,
      interleaved: false)
    try writer.write(from: buffer)
  }
}

/// Resolves to the app bundle in production and to the compiled test bundle in unit tests.
nonisolated private final class IOSAudioResourceAnchor: NSObject {}
