import SalahCore
import SwiftUI
import UIKit

/// The same city selection is used from onboarding, Settings and location recovery.
struct IOSLocationSettingsView: View {
  var onSelected: (() -> Void)? = nil

  @Environment(IOSAppStore.self) private var store
  @Environment(IOSLocationService.self) private var locationService
  @Environment(IOSCitySearchService.self) private var searchService
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var query = ""
  @FocusState private var searchFocused: Bool

  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }
  private var isOnboarding: Bool { onSelected != nil }
  private var isDenied: Bool {
    locationService.authorizationStatus == .denied
      || locationService.authorizationStatus == .restricted
  }
  private var isSearchingCity: Bool {
    query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
  }

  var body: some View {
    Form {
      if isOnboarding {
        Section {
          Text(
            copy.text(
              "Location access is optional. Choose a city for prayer times and the Qibla.",
              "الوصول إلى الموقع اختياري. اختر مدينة لمواقيت الصلاة والقبلة.")
          )
          .font(.footnote)
          .foregroundStyle(IOSTheme.labelSecondary)
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
        }
      }
      Section {
        searchField
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      }

      if isSearchingCity {
        searchResults
      } else if !isOnboarding {
        if isDenied {
          Section {
            Button {
              if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
              IOSSettingsRow(title: copy.text("Open iPhone Settings", "فتح إعدادات iPhone"))
            }
            .accessibilityIdentifier("location.openSettings")
          } header: {
            Text(
              copy.text(
                "Location access is off. Choose a city to calculate its times, or allow location in iPhone Settings. Your selected city remains available.",
                "الوصول إلى الموقع معطّل. اختر مدينة لحساب مواقيتها، أو اسمح بالموقع في إعدادات iPhone. تبقى مدينتك المختارة متاحة."
              )
            )
            .font(.footnote)
          }
        }

        Section {
          Toggle(isOn: currentLocation) {
            IOSSettingsRow(
              title: copy.text("Use current location", "استخدام الموقع الحالي"),
              symbol: "location.fill")
          }
          .disabled(locationService.authorizationStatus == .restricted)
          .accessibilityIdentifier("location.current")
          .disabled(isDenied)
          if locationService.isLocating {
            HStack(spacing: 12) {
              ProgressView()
              Text(copy.text("Finding your location…", "جارٍ تحديد موقعك…"))
                .foregroundStyle(IOSTheme.labelSecondary)
            }
            .accessibilityIdentifier("location.progress")
          }
        } footer: {
          if let error = locationService.errorMessage, !isDenied {
            Text(IOSL10n.text(error, locale: store.locale))
          }
        }

        if let location = store.preferences.location {
          Section(copy.text("Current", "الحالي")) {
            HStack(spacing: 12) {
              IOSSettingsRow(
                title: locationTitle(location),
                subtitle: detail(location), symbol: "mappin.and.ellipse")
              Image(systemName: "checkmark")
                .foregroundStyle(IOSTheme.accent)
                .accessibilityHidden(true)
            }
            .accessibilityIdentifier("location.selected")
            .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
          }
        }

        Section {
          ForEach(recentLocations, id: \.self) { location in
            Button {
              select(location)
            } label: {
              IOSSettingsRow(
                title: locationTitle(location), symbol: "clock")
            }
            .accessibilityIdentifier("location.recent.\(location.timeZone.identifier)")
          }
        } header: {
          if !recentLocations.isEmpty { Text(copy.text("Recent", "الأخيرة")) }
        } footer: {
          Text(
            copy.text(
              "Prayer times are calculated on this iPhone. Current location uses Apple’s location services; city searches use Apple Maps.",
              "تُحسب مواقيت الصلاة على iPhone. يستخدم الموقع الحالي خدمات الموقع من Apple، ويستخدم البحث عن المدن خرائط Apple."
            ))
        }
      }
    }
    .iosSettingsForm()
    .navigationTitle(
      isOnboarding ? copy.text("Choose a city", "اختر مدينة") : copy.text("Location", "الموقع")
    )
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("location.form")
    .onChange(of: query) { _, value in searchService.update(query: value) }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        locationService.refreshAuthorization()
        if isSearchingCity { searchService.update(query: query) }
      }
    }
    .task { locationService.refreshAuthorization() }
    .onDisappear { searchService.cancel() }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.title3)
        .accessibilityHidden(true)
      TextField(copy.text("Search for a city", "ابحث عن مدينة"), text: $query)
        .focused($searchFocused)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .accessibilityIdentifier("location.searchField")
      if !query.isEmpty {
        Button {
          query = ""
          searchService.cancel()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(IOSTheme.labelSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copy.text("Clear search", "مسح البحث"))
        .accessibilityIdentifier("location.clearSearch")
      }
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 48)
    .glassEffect(.regular, in: .capsule)
  }

  @ViewBuilder private var searchResults: some View {
    Section {
      if searchService.isSearching {
        HStack(spacing: 12) {
          ProgressView()
          Text(copy.text("Searching cities…", "جارٍ البحث عن المدن…"))
            .foregroundStyle(IOSTheme.labelSecondary)
        }
        .accessibilityIdentifier("location.searchProgress")
      }
      ForEach(Array(searchService.results.enumerated()), id: \.element.id) { index, result in
        Button {
          select(result.location)
        } label: {
          HStack {
            IOSSettingsRow(
              title: result.title,
              subtitle: [result.subtitle, result.location.timeZone.identifier]
                .filter { !$0.isEmpty }.joined(separator: " · "),
              symbol: isOnboarding ? nil : "mappin.and.ellipse")
            if isOnboarding {
              Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(IOSTheme.labelTertiary)
                .accessibilityHidden(true)
            }
          }
        }
        .accessibilityIdentifier("location.result.\(index)")
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
      }
      if let error = searchService.errorMessage {
        Text(IOSL10n.text(error, locale: store.locale))
          .foregroundStyle(IOSTheme.labelSecondary)
          .accessibilityIdentifier("location.searchError")
        Button(copy.text("Try again", "حاول مجددًا")) { searchService.update(query: query) }
          .accessibilityIdentifier("location.retrySearch")
      }
    } header: {
      Text(copy.text("Search results", "نتائج البحث"))
    } footer: {
      Text(
        isOnboarding
          ? copy.text(
            "Times follow the city’s time zone. You can change the city later.",
            "تتبع المواقيت المنطقة الزمنية للمدينة. يمكنك تغيير المدينة لاحقًا.")
          : copy.text(
            "Choose the correct city and time zone. Search uses Apple Maps. Prayer times work offline once a city is selected.",
            "اختر المدينة والمنطقة الزمنية الصحيحتين. يستخدم البحث خرائط Apple. تعمل المواقيت دون اتصال بعد اختيار المدينة."
          ))
    }
  }

  private var currentLocation: Binding<Bool> {
    Binding(
      get: { store.preferences.useCurrentLocation && !isDenied },
      set: { enabled in
        store.updatePreferences { $0.useCurrentLocation = enabled }
        if enabled {
          locationService.requestLocation()
        } else {
          locationService.cancelLocation()
        }
      })
  }

  private var recentLocations: [PrayerLocation] {
    store.preferences.recentLocations.filter { $0 != store.preferences.location }
  }

  private func select(_ location: PrayerLocation) {
    locationService.cancelLocation()
    searchService.cancel()
    searchFocused = false
    query = ""
    store.select(location: location)
    onSelected?()
  }

  private func detail(_ location: PrayerLocation) -> String {
    let latitude = abs(location.latitude).formatted(
      .number.precision(.fractionLength(4)).locale(store.locale))
    let longitude = abs(location.longitude).formatted(
      .number.precision(.fractionLength(4)).locale(store.locale))
    return
      "\(latitude)° \(location.latitude >= 0 ? "N" : "S"), \(longitude)° \(location.longitude >= 0 ? "E" : "W") · \(location.timeZone.identifier)"
  }

  private func locationTitle(_ location: PrayerLocation) -> String {
    let name = location.name ?? copy.text("Selected location", "الموقع المختار")
    guard let countryCode = location.countryCode,
      let country = store.locale.localizedString(forRegionCode: countryCode),
      !country.isEmpty, !name.localizedCaseInsensitiveContains(country)
    else { return name }
    return name + (copy.isArabic ? "، " : ", ") + country
  }
}
