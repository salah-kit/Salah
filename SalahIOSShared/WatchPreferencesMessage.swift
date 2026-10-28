import Foundation

/// What the iPhone app sends its watch app over WatchConnectivity: the whole preferences, as
/// JSON under a versioned key, and when they were sent.
///
/// The iPhone sends it as the session's application context, which keeps only the latest, and
/// in reply to the watch's request for it. The watch keeps its own copy, so it works from the
/// last preferences it received while the iPhone app is closed or the iPhone is away.
nonisolated struct WatchPreferencesMessage: Equatable, Sendable {
  /// The key of the preferences' JSON. A change to their shape takes a new key.
  static let preferencesKey = "preferences.v1"
  /// The key of the instant the iPhone sent them.
  static let sentKey = "sent"
  /// The key of the watch's request for the preferences, a message the iPhone answers.
  static let requestKey = "request.preferences.v1"

  var preferences: IOSPreferences
  var sentAt: Date

  /// Why a context can't be read.
  enum ReadError: Error, Equatable, Sendable {
    /// It holds no preferences, such as the reply of an iPhone that isn't set up.
    case noPreferences
    /// Its preferences or date don't decode, such as from a newer app's shape.
    case unreadable
  }

  init(preferences: IOSPreferences, sentAt: Date) {
    self.preferences = preferences
    self.sentAt = sentAt
  }

  /// Reads a received context or reply.
  init(context: [String: Any]) throws(ReadError) {
    guard let data = context[Self.preferencesKey] as? Data else { throw .noPreferences }
    guard let sentAt = context[Self.sentKey] as? Date,
      let preferences = try? JSONDecoder().decode(IOSPreferences.self, from: data)
    else { throw .unreadable }
    self.init(preferences: preferences.normalized(), sentAt: sentAt)
  }

  /// The context to send: property-list values only, as WatchConnectivity requires.
  func context() throws -> [String: Any] {
    [Self.preferencesKey: try JSONEncoder().encode(preferences), Self.sentKey: sentAt]
  }
}
