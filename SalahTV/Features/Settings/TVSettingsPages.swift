import SalahCalculation
import SalahCore
import SalahTimes
import SwiftUI

/// The page a Settings row opens.
struct TVSettingsPage: View {
  let route: TVSettingsRoute
  @Environment(IOSAppStore.self) private var store

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    Group {
      switch route {
      case .location: TVLocationSettingsPage()
      case .citySearch: TVCitySearchView(completesOnboarding: false)
      case .method: TVMethodPage()
      case .angle(let kind): TVAnglePage(kind: kind)
      case .madhab:
        TVChoicePage(
          title: copy.text("Asr (madhab)", "العصر (المذهب)"),
          options: [
            .init(
              value: Madhab.shafi,
              title: copy.text("Shafi’i, Maliki, Hanbali", "شافعي، مالكي، حنبلي"),
              detail: copy.text(
                "Asr when a shadow equals its object’s length", "العصر عندما يساوي الظل طول الجسم")),
            .init(
              value: Madhab.hanafi, title: copy.text("Hanafi", "حنفي"),
              detail: copy.text(
                "Asr when a shadow is twice its object’s length",
                "العصر عندما يساوي الظل ضعفي طول الجسم")),
          ],
          selected: store.preferences.madhab
        ) { value in store.updatePreferences { $0.madhab = value } }
      case .highLatitude:
        TVChoicePage(
          title: copy.text("High latitudes", "خطوط العرض العليا"),
          options: HighLatitudeRule.allCases.map {
            .init(value: $0, title: copy.highLatitude($0), detail: highLatitudeDetail($0, copy))
          },
          selected: store.preferences.automaticHighLatitude
            ? .recommended : store.preferences.highLatitudeRule
        ) { rule in
          store.updatePreferences {
            $0.automaticHighLatitude = rule == .recommended
            $0.highLatitudeRule = rule
          }
        }
      case .adjustments: TVAdjustmentsPage()
      case .adjustment(let kind):
        TVChoicePage(
          title: store.names.name(of: kind),
          options: IOSPreferences.adjustmentMinutes.map {
            .init(value: $0, title: copy.signedMinutes($0))
          },
          selected: store.preferences.adjustments.settingsMinutes(for: kind)
        ) { minutes in
          store.updatePreferences { $0.adjustments.setSettingsMinutes(minutes, for: kind) }
        }
      case .prayers: TVPrayersPage()
      case .prayer(let kind, let observance): TVPrayerAdhanPage(kind: kind, observance: observance)
      case .volume:
        TVChoicePage(
          title: copy.text("Volume", "مستوى الصوت"),
          options: [0.25, 0.5, 0.75, 1].map { .init(value: $0, title: copy.volume($0)) },
          selected: store.preferences.playbackVolume
        ) { volume in store.updatePreferences { $0.playbackVolume = volume } }
      case .appearance:
        TVChoicePage(
          title: copy.text("Appearance", "المظهر"),
          options: SalahAppearance.allCases.map { .init(value: $0, title: copy.appearance($0)) },
          selected: store.preferences.appearance
        ) { appearance in store.updatePreferences { $0.appearance = appearance } }
      case .language:
        TVChoicePage(
          title: copy.text("Language", "اللغة"),
          options: AppLanguage.allCases.map { .init(value: $0, title: copy.language($0)) },
          selected: store.preferences.language
        ) { language in store.updatePreferences { $0.language = language } }
      case .hijri:
        TVChoicePage(
          title: copy.text("Hijri date", "التاريخ الهجري"),
          options: (-3...3).map { .init(value: $0, title: copy.hijriOffset($0)) },
          selected: store.preferences.hijriOffset,
          footer: copy.text(
            "Add or subtract up to 3 days for your local moon sighting. This also adjusts when Ramadan begins.",
            "أضف أو اطرح حتى ٣ أيام وفق رؤية الهلال المحلية. يعدّل هذا أيضًا بداية رمضان.")
        ) { offset in store.updatePreferences { $0.hijriOffset = offset } }
      case .about: TVAboutPage()
      }
    }
    .background { TVSkyBackground(phase: .neutral) }
  }

  private func highLatitudeDetail(_ rule: HighLatitudeRule, _ copy: TVSettingsCopy) -> String {
    switch rule {
    case .recommended:
      copy.text(
        "Seventh of the night above 48°; middle of the night elsewhere",
        "سُبع الليل بعد ٤٨°؛ ومنتصف الليل فيما عدا ذلك")
    case .middleOfTheNight:
      copy.text("Limit twilight to half the night", "تحديد الشفق بنصف الليل")
    case .seventhOfTheNight:
      copy.text("Limit twilight to a seventh of the night", "تحديد الشفق بسُبع الليل")
    case .twilightAngle:
      copy.text("Use the twilight angle divided by 60", "استخدام زاوية الشفق مقسومة على ٦٠")
    case .disabled:
      copy.text(
        "Some events may not occur at high latitudes",
        "قد لا تحدث بعض المواقيت في خطوط العرض العليا")
    }
  }
}

/// One choice among values: a list of rows with a checkmark on the selected one.
struct TVChoicePage<Value: Hashable>: View {
  struct Option: Identifiable {
    var value: Value
    var title: String
    var detail: String? = nil
    var id: Value { value }
  }

  let title: String
  let options: [Option]
  let selected: Value
  var footer: String? = nil
  let select: (Value) -> Void
  @FocusState private var focused: Value?

  var body: some View {
    List {
      Section {
        ForEach(options) { option in
          Button {
            select(option.value)
          } label: {
            HStack(spacing: 24) {
              VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: option.title)
                if let detail = option.detail {
                  Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              Spacer(minLength: 0)
              if option.value == selected {
                Image(systemName: "checkmark").accessibilityHidden(true)
              }
            }
          }
          .focused($focused, equals: option.value)
          .accessibilityAddTraits(option.value == selected ? .isSelected : [])
        }
      } footer: {
        if let footer { Text(verbatim: footer) }
      }
    }
    .navigationTitle(title)
    .frame(maxWidth: 1120)
    .defaultFocus($focused, selected)
  }
}

/// Where the times are for: this Apple TV's location once, or a city.
struct TVLocationSettingsPage: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(TVAppRuntime.self) private var runtime
  @Environment(TVLocationService.self) private var location

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    List {
      if let current = store.preferences.location {
        Section(copy.text("Times for", "الأوقات لمدينة")) {
          Text(verbatim: TVPlaceName(location: current, locale: store.locale).full)
            .foregroundStyle(.secondary)
        }
      }
      Section {
        Button {
          runtime.useCurrentLocation()
        } label: {
          HStack {
            Label(
              copy.text("Use This Apple TV’s Location", "استخدام موقع جهاز Apple TV هذا"),
              systemImage: "location.fill")
            Spacer()
            if location.isLocating { ProgressView() }
          }
        }
        .accessibilityIdentifier("location.current")
        NavigationLink(value: TVSettingsRoute.citySearch) {
          Label(copy.text("Choose a City", "اختيار مدينة"), systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("location.search")
      } footer: {
        if let error = location.errorMessage {
          Text(verbatim: error.message(copy.copy))
        } else {
          Text(
            verbatim: copy.text(
              "Salah uses this Apple TV’s location once to find your city and its time zone. Choosing a city needs no permission.",
              "يستخدم تطبيق صلاة موقع جهاز Apple TV هذا مرة واحدة لمعرفة مدينتك ومنطقتها الزمنية. واختيار مدينة لا يحتاج إلى إذن."
            ))
        }
      }
      let recent = store.preferences.recentLocations.filter { $0 != store.preferences.location }
      if !recent.isEmpty {
        Section(copy.text("Recent", "الأخيرة")) {
          ForEach(recent, id: \.self) { place in
            Button(TVPlaceName(location: place, locale: store.locale).full) {
              runtime.choose(city: place)
            }
          }
        }
      }
    }
    .navigationTitle(copy.text("Location", "الموقع"))
    .frame(maxWidth: 1120)
  }
}

/// A place's name with its country: "London, United Kingdom".
nonisolated struct TVPlaceName {
  let location: PrayerLocation
  let locale: Locale

  var full: String {
    [location.name, location.countryCode.flatMap { locale.localizedString(forRegionCode: $0) }]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
  }
}

/// The calculation methods, and the custom angles when Custom is chosen.
struct TVMethodPage: View {
  @Environment(IOSAppStore.self) private var store
  @FocusState private var focused: IOSCalculationMethod?

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    let preferences = store.preferences
    List {
      Section {
        ForEach(IOSCalculationMethod.allCases, id: \.self) { method in
          Button {
            store.updatePreferences { $0.method = method }
          } label: {
            HStack(spacing: 24) {
              VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: method.title(locale: store.locale))
                if method == .automatic {
                  Text(
                    verbatim: IOSCalculationMethod.preset(preferences.resolvedMethod).title(
                      locale: store.locale)
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
              }
              Spacer(minLength: 0)
              if preferences.method == method {
                Image(systemName: "checkmark").accessibilityHidden(true)
              }
            }
          }
          .focused($focused, equals: method)
          .accessibilityAddTraits(preferences.method == method ? .isSelected : [])
        }
      }
      if preferences.method == .custom {
        Section(copy.text("Custom angles", "زوايا مخصصة")) {
          NavigationLink(value: TVSettingsRoute.angle(.fajr)) {
            angleRow(copy.text("Fajr angle", "زاوية الفجر"), preferences.customFajrAngle, copy)
          }
          NavigationLink(value: TVSettingsRoute.angle(.isha)) {
            angleRow(copy.text("Isha angle", "زاوية العشاء"), preferences.customIshaAngle, copy)
          }
        }
      }
    }
    .navigationTitle(copy.text("Method", "الطريقة"))
    .frame(maxWidth: 1120)
    .defaultFocus($focused, preferences.method)
  }

  private func angleRow(_ title: String, _ value: Double, _ copy: TVSettingsCopy) -> some View {
    HStack {
      Text(verbatim: title)
      Spacer()
      Text(verbatim: copy.number(value) + "°").foregroundStyle(.secondary)
    }
  }
}

/// A custom twilight angle, in half degrees.
struct TVAnglePage: View {
  let kind: PrayerKind
  @Environment(IOSAppStore.self) private var store

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    let values = stride(from: 10.0, through: 22.0, by: 0.5).map { $0 }
    TVChoicePage(
      title: kind == .fajr
        ? copy.text("Fajr angle", "زاوية الفجر") : copy.text("Isha angle", "زاوية العشاء"),
      options: values.map { .init(value: $0, title: copy.number($0) + "°") },
      selected: kind == .fajr
        ? store.preferences.customFajrAngle : store.preferences.customIshaAngle
    ) { angle in
      store.updatePreferences {
        if kind == .fajr { $0.customFajrAngle = angle } else { $0.customIshaAngle = angle }
      }
    }
  }
}

/// Each prayer's minutes, to match a mosque's timetable.
struct TVAdjustmentsPage: View {
  @Environment(IOSAppStore.self) private var store

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    List {
      ForEach(PrayerKind.allCases, id: \.self) { kind in
        NavigationLink(value: TVSettingsRoute.adjustment(kind)) {
          HStack {
            Text(verbatim: store.names.name(of: kind))
            Spacer()
            Text(
              verbatim: copy.signedMinutes(store.preferences.adjustments.settingsMinutes(for: kind))
            )
            .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle(copy.text("Adjustments", "التعديلات"))
    .frame(maxWidth: 1120)
  }
}

/// The prayers and the sound each plays while Salah is open.
struct TVPrayersPage: View {
  @Environment(IOSAppStore.self) private var store

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    List {
      ForEach(PrayerKind.allCases, id: \.self) { kind in
        NavigationLink(value: TVSettingsRoute.prayer(kind, .ordinary)) {
          HStack {
            Text(verbatim: store.names.name(of: kind))
            Spacer()
            Text(verbatim: summary(kind, copy)).foregroundStyle(.secondary)
          }
        }
        .accessibilityIdentifier("prayers.\(kind.rawValue)")
      }
    }
    .navigationTitle(copy.text("Prayers", "الصلوات"))
    .frame(maxWidth: 1120)
  }

  private func summary(_ kind: PrayerKind, _ copy: TVSettingsCopy) -> String {
    copy.sound(store.preferences.tvSound(for: kind))
  }
}

/// One prayer's sound while Salah is open: Off, or an adhan or the soft tone.
struct TVPrayerAdhanPage: View {
  let kind: PrayerKind
  let observance: PrayerObservance
  @Environment(IOSAppStore.self) private var store
  @Environment(TVAppRuntime.self) private var runtime
  @FocusState private var focused: IOSSound?

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    let selected = store.preferences.tvSound(for: kind, observance: observance)
    let name =
      observance == .jumuah ? store.names.string(for: .jumuah) : store.names.name(of: kind)
    List {
      Section {
        ForEach(TVAudioService.sounds, id: \.self) { sound in
          Button {
            choose(sound)
            if sound != .none { runtime.preview(sound) } else { runtime.stopSound() }
          } label: {
            HStack {
              Text(verbatim: copy.sound(sound))
              Spacer()
              if sound == selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
          }
          .focused($focused, equals: sound)
          .accessibilityAddTraits(sound == selected ? .isSelected : [])
          .accessibilityIdentifier("prayer.sound.\(Self.identifier(sound))")
        }
      } footer: {
        Text(verbatim: footer(copy))
      }
    }
    .navigationTitle(name)
    .frame(maxWidth: 1120)
    .defaultFocus($focused, selected)
    .onDisappear { runtime.stopSound() }
  }

  private func footer(_ copy: TVSettingsCopy) -> String {
    var lines = [
      copy.text(
        "Plays at the prayer’s time while Salah is open. Choosing a sound plays it once.",
        "يُشغَّل عند وقت الصلاة ما دام تطبيق صلاة مفتوحًا. اختيار صوت يشغّله مرة واحدة.")
    ]
    if store.preferences.muteSounds {
      lines.append(
        copy.text(
          "Adhan on this Apple TV is off in Settings.",
          "الأذان على جهاز Apple TV هذا متوقف في الإعدادات."))
    }
    if observance == .jumuah, !store.preferences.jumuahOverrideEnabled {
      lines.append(
        copy.text(
          "On Fridays, Jumu’ah uses Dhuhr’s sound.", "يوم الجمعة، تستخدم صلاة الجمعة صوت الظهر."))
    }
    return lines.joined(separator: " ")
  }

  private func choose(_ sound: IOSSound) {
    store.updatePreferences { $0.setTVSound(sound, for: kind, observance: observance) }
  }

  static func identifier(_ sound: IOSSound) -> String {
    switch sound {
    case .adhan: "adhan"
    case .fajrAdhan: "fajrAdhan"
    case .softTone: "softTone"
    case .system: "system"
    case .none: "none"
    case .custom: "custom"
    }
  }
}
