import Darwin
import Foundation
import SalahWidgets

nonisolated enum IOSPreferencesStorageError: Error, Equatable {
  case unsupportedVersion(Int)
  case appGroupUnavailable
  case lockFailed
}

/// One file is the preferences owner in the app and its intents. The lock covers the
/// entire read-modify-write, including separate processes; atomic replacement protects
/// readers if a process exits while writing.
nonisolated struct IOSSharedPreferencesStore: Sendable {
  static let changedSignalName = "io.github.salah-kit.Salah.ios.preferencesChanged"

  static var live: Self {
    Self(
      directory: FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SalahWidgetConstants.appGroupID))
  }

  let directory: URL?

  nonisolated private struct Envelope: Codable {
    var schemaVersion: Int
    var preferences: IOSPreferences
  }
  nonisolated private struct Version: Decodable { var schemaVersion: Int }

  func load() throws -> IOSPreferences? { try locked { try read(from: $0) } }

  func save(_ preferences: IOSPreferences) throws {
    try locked { url in
      // Reading first prevents an older app from overwriting a newer schema.
      _ = try readForUpdate(from: url)
      try write(preferences.normalized(), to: url)
    }
    DarwinSignal(name: Self.changedSignalName).post()
  }

  @discardableResult
  func update(_ change: (inout IOSPreferences) -> Void) throws -> IOSPreferences {
    let result = try locked { url in
      var preferences = try readForUpdate(from: url) ?? IOSPreferences()
      change(&preferences)
      preferences = preferences.normalized()
      try write(preferences, to: url)
      return preferences
    }
    DarwinSignal(name: Self.changedSignalName).post()
    return result
  }

  private func locked<T>(_ operation: (URL) throws -> T) throws -> T {
    guard let directory else { throw IOSPreferencesStorageError.appGroupUnavailable }
    let folder = directory.appendingPathComponent(
      "Library/Application Support/Salah", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let lockURL = folder.appendingPathComponent("preferences.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw IOSPreferencesStorageError.lockFailed }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw IOSPreferencesStorageError.lockFailed }
    defer { flock(descriptor, LOCK_UN) }
    return try operation(folder.appendingPathComponent("preferences-v1.json"))
  }

  private func read(from url: URL) throws -> IOSPreferences? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let version = try JSONDecoder().decode(Version.self, from: data).schemaVersion
    guard version == 1 else { throw IOSPreferencesStorageError.unsupportedVersion(version) }
    return try JSONDecoder().decode(Envelope.self, from: data).preferences
  }

  private func write(_ preferences: IOSPreferences, to url: URL) throws {
    let data = try JSONEncoder().encode(Envelope(schemaVersion: 1, preferences: preferences))
    try data.write(to: url, options: .atomic)
  }

  /// A failed decode is visible on load. An explicit subsequent edit can recover,
  /// retaining the unreadable bytes for recovery instead of trapping all future saves.
  private func readForUpdate(from url: URL) throws -> IOSPreferences? {
    do {
      return try read(from: url)
    } catch let error as IOSPreferencesStorageError {
      // A newer schema is valid data owned by a newer app, never a corrupt file.
      throw error
    } catch is DecodingError {
      let backup = url.deletingLastPathComponent()
        .appendingPathComponent("preferences-unreadable-\(UUID().uuidString).json")
      try FileManager.default.copyItem(at: url, to: backup)
      return nil
    }
  }
}
