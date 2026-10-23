import Foundation

@MainActor
protocol IOSPreferencesRepository {
  func load() throws -> IOSPreferences?
  func save(_ preferences: IOSPreferences) throws
  func update(_ change: (inout IOSPreferences) -> Void) throws -> IOSPreferences
}

extension IOSPreferencesRepository {
  func update(_ change: (inout IOSPreferences) -> Void) throws -> IOSPreferences {
    var preferences = try load() ?? IOSPreferences()
    change(&preferences)
    preferences = preferences.normalized()
    try save(preferences)
    return preferences
  }
}

@MainActor
final class IOSAppGroupPreferencesRepository: IOSPreferencesRepository {
  private let shared: IOSSharedPreferencesStore

  init(shared: IOSSharedPreferencesStore = .live) { self.shared = shared }
  func load() throws -> IOSPreferences? { try shared.load() }
  func save(_ preferences: IOSPreferences) throws { try shared.save(preferences) }
  func update(_ change: (inout IOSPreferences) -> Void) throws -> IOSPreferences {
    try shared.update(change)
  }
}

typealias IOSSharedPreferencesRepository = IOSAppGroupPreferencesRepository

/// Versioned local storage. Shared widget settings are a derived mirror, not a second owner.
@MainActor
final class IOSUserDefaultsPreferencesRepository: IOSPreferencesRepository {
  static let key = "Salah.iOS.preferences.v1"
  private let defaults: UserDefaults

  nonisolated private struct Envelope: Codable {
    var schemaVersion: Int
    var preferences: IOSPreferences
  }

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func load() throws -> IOSPreferences? {
    guard let data = defaults.data(forKey: Self.key) else { return nil }
    let version = try JSONDecoder().decode(Version.self, from: data).schemaVersion
    guard version == 1 else { throw IOSPreferencesStorageError.unsupportedVersion(version) }
    return try JSONDecoder().decode(Envelope.self, from: data).preferences
  }

  func save(_ preferences: IOSPreferences) throws {
    if let data = defaults.data(forKey: Self.key),
      let version = try? JSONDecoder().decode(Version.self, from: data).schemaVersion,
      version > 1
    {
      throw IOSPreferencesStorageError.unsupportedVersion(version)
    }
    let data = try JSONEncoder().encode(Envelope(schemaVersion: 1, preferences: preferences))
    defaults.set(data, forKey: Self.key)
  }

  nonisolated private struct Version: Decodable { var schemaVersion: Int }
}
