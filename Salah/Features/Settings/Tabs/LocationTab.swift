import AppKit
import MapKit
import SwiftUI

struct LocationContent: View {
  @Bindable var prefs = Preferences.shared
  @State private var locationSearch = LocationSearchService()
  @FocusState private var isSearchFocused: Bool

  private let timeZoneChoices = TimeZone.knownTimeZoneIdentifiers
    .map(TimeZoneChoice.init(identifier:))
    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

  var body: some View {
    @Bindable var search = locationSearch

    Section {
      Toggle(isOn: $prefs.useCurrentLocation) {
        Text("settings.location.useCurrent")
        Text("settings.location.useCurrent.detail")
      }
      .settingsRow(detail: true, last: FailureReporter.shared.currentNotice?.domain != .location)

      if let notice = FailureReporter.shared.currentNotice, notice.domain == .location {
        InlineNoticeLabel(message: notice.message)
        if notice.category == .terminal {
          Button("settings.location.openSystemSettings") {
            openLocationSystemSettings()
          }
          .settingsPushButton()
          .settingsRow(last: true)
        }
      }
    } header: {
      SettingsHeader("settings.location.detection", isFirst: true)
    }
    .onChange(of: prefs.useCurrentLocation) {
      if prefs.useCurrentLocation {
        NotificationCenter.default.post(name: .startLocationUpdate, object: nil)
        locationSearch.cancel()
        isSearchFocused = false
      } else {
        NotificationCenter.default.post(name: .stopLocationUpdate, object: nil)
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)
    ) { _ in
      if prefs.useCurrentLocation {
        NotificationCenter.default.post(name: .startLocationUpdate, object: nil)
      }
    }

    if !prefs.useCurrentLocation {
      Section {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.tertiary)
            .font(.system(size: 12))

          TextField(
            localizedString("settings.location.searchPlaceholder", locale: .app),
            text: $search.searchText
          )
          .textFieldStyle(.plain)
          .multilineTextAlignment(.leading)
          .focused($isSearchFocused)

          if locationSearch.isSearching || locationSearch.isResolving {
            ProgressView()
              .controlSize(.small)
          } else if !locationSearch.searchText.isEmpty {
            Button {
              locationSearch.cancel()
              isSearchFocused = true
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = true }

        ForEach(locationSearch.completions.prefix(5), id: \.self) { completion in
          Button {
            Task { await locationSearch.selectCompletion(completion) }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(completion.title)
              if !completion.subtitle.isEmpty {
                Text(completion.subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }

        if let error = locationSearch.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
        }
      } header: {
        SettingsHeader("settings.location.search")
      }
      .onChange(of: locationSearch.searchText) {
        locationSearch.updateCompleter()
      }
      // Drop a stale search error message when the language changes - it was
      // built against the old locale and would otherwise sit there frozen.
      .onChange(of: prefs.appLanguage) { locationSearch.errorMessage = nil }
    }

    Section {
      LabeledContent("settings.location.city", value: prefs.placeCity(locale: .app))
        .settingsRow()
      LabeledContent(
        "settings.location.region",
        value: LocationText.pair(
          prefs.placeRegion(locale: .app), prefs.placeCountry(locale: .app), locale: .app)
      )
      .settingsRow()
      LabeledContent(
        "settings.location.coordinates",
        value: LocationText.coordinates(
          latitude: prefs.latitude, longitude: prefs.longitude, locale: .app)
      )
      .settingsRow()
      LabeledContent("settings.location.timeZone") {
        if prefs.useCurrentLocation {
          Text(verbatim: LocationText.timeZone(prefs.storedTimeZone, locale: .app))
        } else {
          // Labelled for VoiceOver; the row's own label shows it.
          Picker("settings.location.timeZone", selection: $prefs.storedTimeZone) {
            ForEach(timeZoneChoices) { choice in
              Text(choice.title).tag(choice.identifier)
            }
          }
          .labelsHidden()
          .settingsPopUp()
          .environment(\.layoutDirection, .leftToRight)
        }
      }
      .settingsRow(last: true)
    } header: {
      SettingsHeader("settings.location.current")
    }
  }

  private func openLocationSystemSettings() {
    let urlStrings = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
      "x-apple.systempreferences:com.apple.preference.security",
    ]
    for urlString in urlStrings {
      guard let url = URL(string: urlString) else { continue }
      if NSWorkspace.shared.open(url) { return }
    }
  }
}

private struct TimeZoneChoice: Identifiable {
  let identifier: String
  let title: String

  nonisolated var id: String { identifier }

  nonisolated init(identifier: String) {
    self.identifier = identifier
    title =
      identifier
      .split(separator: "/")
      .last
      .map { $0.replacingOccurrences(of: "_", with: " ") }
      ?? identifier
  }
}

/// How the Location pane writes a place, in the language Salah shows.
enum LocationText {
  /// "Makkah, Saudi Arabia" / "مكة المكرمة، السعودية": two parts with the language's comma,
  /// or the one that isn't empty.
  static func pair(_ first: String, _ second: String, locale: Locale) -> String {
    if first.isEmpty || second.isEmpty { return first.isEmpty ? second : first }
    return String(
      format: localizedString("settings.location.pair", locale: locale), locale: locale, first,
      second)
  }

  /// "21.4167, 39.8167" / "٢١٫٤١٦٧، ٣٩٫٨١٦٧": four decimals in the language's digits.
  static func coordinates(latitude: Double, longitude: Double, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 4
    formatter.maximumFractionDigits = 4
    let text = { (value: Double) in formatter.string(from: NSNumber(value: value)) ?? "" }
    return pair(text(latitude), text(longitude), locale: locale)
  }

  /// The time zone: its identifier ("Asia/Riyadh") in a language written in Latin script,
  /// as macOS shows it, and in another script the zone's city in that language ("توقيت
  /// الرياض"), since an identifier in Latin letters doesn't read in it.
  static func timeZone(_ identifier: String, locale: Locale) -> String {
    guard locale.language.script != .latin, let zone = TimeZone(identifier: identifier) else {
      return identifier
    }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = zone
    formatter.dateFormat = "VVV"
    let city = formatter.string(from: Date(timeIntervalSince1970: 0))
    return String(
      format: localizedString("settings.location.timeZone.city", locale: locale), locale: locale,
      city)
  }
}
