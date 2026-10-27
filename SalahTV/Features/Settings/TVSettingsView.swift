import SalahCore
import SalahTimes
import SwiftUI

/// A page Settings opens.
nonisolated enum TVSettingsRoute: Hashable, Sendable {
  case location, citySearch, method
  case angle(PrayerKind)
  case madhab, highLatitude, adjustments
  case adjustment(PrayerKind)
  case prayers
  case prayer(PrayerKind, PrayerObservance)
  case volume, appearance, language, hijri, about
}

/// A row on the Settings list, which the panel beside it describes while it has focus.
nonisolated enum TVSettingsItem: Hashable, Sendable {
  case location, method, madhab, highLatitude, adjustments, ramadanIsha
  case adhan, prayers, dua, volume
  case appearance, language, timeOfDay, hijri, about
}

/// Settings as a split view: what the focused row does on the left, the grouped list on the
/// right. Every choice is a row, because tvOS has no slider, stepper or switch.
struct TVSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(TVNavigation.self) private var navigation
  @FocusState private var focused: TVSettingsItem?

  var body: some View {
    @Bindable var navigation = navigation
    NavigationStack(path: $navigation.settingsPath) {
      HStack(alignment: .top, spacing: 100) {
        TVSettingsDetailPanel(item: focused ?? .location)
          .frame(width: 540, alignment: .leading)
          .padding(.top, 150)
        list
          .frame(width: 1120)
      }
      .padding(.horizontal, TVMetrics.safeHorizontal)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background { TVSkyBackground(phase: .neutral) }
      .navigationDestination(for: TVSettingsRoute.self) { route in
        TVSettingsPage(route: route)
      }
    }
  }

  private var list: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    let preferences = store.preferences
    return List {
      Section(copy.text("Place", "المكان")) {
        row(.location, copy.text("Location", "الموقع"), value: preferences.location?.name)
      }
      Section(copy.text("Prayer times", "أوقات الصلاة")) {
        row(.method, copy.text("Method", "الطريقة"), value: copy.method(preferences))
        row(
          .madhab, copy.text("Asr (madhab)", "العصر (المذهب)"),
          value: copy.madhab(preferences.madhab))
        row(
          .highLatitude, copy.text("High latitudes", "خطوط العرض العليا"),
          value: copy.highLatitude(
            preferences.automaticHighLatitude ? .recommended : preferences.highLatitudeRule))
        row(
          .adjustments, copy.text("Adjustments", "التعديلات"),
          value: copy.adjustments(preferences.adjustments))
        if preferences.offersDelayedIsha {
          toggle(
            .ramadanIsha, copy.text("Delay Isha in Ramadan", "تأخير العشاء في رمضان"),
            \.delayedIshaInRamadan)
        }
      }
      Section(copy.text("Sound", "الصوت")) {
        Toggle(
          copy.text("Adhan on this Apple TV", "الأذان على جهاز Apple TV هذا"),
          isOn: Binding(
            get: { !store.preferences.muteSounds },
            set: { on in store.updatePreferences { $0.muteSounds = !on } })
        )
        .toggleStyle(TVSwitchStyle(copy: copy))
        .focused($focused, equals: .adhan)
        .accessibilityHint(hint(.adhan))
        .accessibilityIdentifier("settings.adhan")
        row(.prayers, copy.text("Prayers", "الصلوات"), value: prayersSummary(copy))
        toggle(.dua, copy.text("Du’a after the adhan", "الدعاء بعد الأذان"), \.duaEnabled)
        row(
          .volume, copy.text("Volume", "مستوى الصوت"),
          value: copy.volume(preferences.playbackVolume))
      }
      Section(copy.text("Display", "العرض")) {
        row(
          .appearance, copy.text("Appearance", "المظهر"),
          value: copy.appearance(preferences.appearance))
        row(.language, copy.text("Language", "اللغة"), value: copy.language(preferences.language))
        toggle(
          .timeOfDay, copy.text("Sky follows the time of day", "السماء تتبع وقت اليوم"),
          \.followsTimeOfDay)
        row(
          .hijri, copy.text("Hijri date", "التاريخ الهجري"),
          value: copy.hijriOffset(preferences.hijriOffset))
      }
      Section {
        row(.about, copy.text("About Salah", "عن صلاة"), value: nil)
      }
    }
    .contentMargins(.top, 150, for: .scrollContent)
    .contentMargins(.bottom, TVMetrics.safeVertical, for: .scrollContent)
  }

  private func row(_ item: TVSettingsItem, _ title: String, value: String?) -> some View {
    NavigationLink(value: Self.route(for: item)) {
      HStack {
        Text(verbatim: title)
        Spacer(minLength: 24)
        if let value {
          Text(verbatim: value)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .focused($focused, equals: item)
    .accessibilityHint(hint(item))
    .accessibilityIdentifier("settings.\(item)")
  }

  private func toggle(
    _ item: TVSettingsItem, _ title: String, _ keyPath: WritableKeyPath<IOSPreferences, Bool>
  ) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { store.preferences[keyPath: keyPath] },
        set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
    )
    .toggleStyle(TVSwitchStyle(copy: TVSettingsCopy(locale: store.locale)))
    .focused($focused, equals: item)
    .accessibilityHint(hint(item))
    .accessibilityIdentifier("settings.\(item)")
  }

  /// The panel's sentence, which VoiceOver doesn't read from the panel itself.
  private func hint(_ item: TVSettingsItem) -> String {
    TVSettingsDetailPanel.detail(
      for: item, copy: TVSettingsCopy(locale: store.locale), store: store
    )
    .text
  }

  private func prayersSummary(_ copy: TVSettingsCopy) -> String {
    copy.copy.format("%@ on", "%@ مفعّلة", copy.number(store.preferences.tvSoundsOn))
  }

  private static func route(for item: TVSettingsItem) -> TVSettingsRoute {
    switch item {
    case .location: .location
    case .method: .method
    case .madhab: .madhab
    case .highLatitude: .highLatitude
    case .adjustments: .adjustments
    case .prayers, .adhan, .dua, .ramadanIsha, .timeOfDay: .prayers
    case .volume: .volume
    case .appearance: .appearance
    case .language: .language
    case .hijri: .hijri
    case .about: .about
    }
  }
}

/// What the focused row does: its symbol, its name and a sentence.
struct TVSettingsDetailPanel: View {
  let item: TVSettingsItem
  @Environment(IOSAppStore.self) private var store

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    let detail = Self.detail(for: item, copy: copy, store: store)
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: detail.symbol)
        .font(.system(size: 96))
        .foregroundStyle(TVTheme.accentText)
        .frame(height: 120)
        .accessibilityHidden(true)
      Text(verbatim: detail.title)
        .font(.title2.bold())
        .foregroundStyle(TVTheme.labelPrimary)
      Text(verbatim: detail.text)
        .font(.callout.weight(.medium))
        .foregroundStyle(TVTheme.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityHidden(true)
  }

  static func detail(for item: TVSettingsItem, copy: TVSettingsCopy, store: IOSAppStore)
    -> (symbol: String, title: String, text: String)
  {
    switch item {
    case .location:
      let place =
        store.display.map { TVSourceNote(display: $0, preferences: store.preferences).place } ?? ""
      return (
        "location.fill", copy.text("Location", "الموقع"),
        place.isEmpty
          ? copy.text(
            "Choose a city, or use this Apple TV’s location once.",
            "اختر مدينة، أو استخدم موقع جهاز Apple TV هذا مرة واحدة.")
          : copy.copy.format(
            "Times for %@. Choose a city, or use this Apple TV’s location once.",
            "الأوقات لمدينة %@. اختر مدينة، أو استخدم موقع جهاز Apple TV هذا مرة واحدة.", place)
      )
    case .method:
      return (
        "globe", copy.text("Method", "الطريقة"),
        copy.text(
          "How Fajr and Isha are calculated. Automatic follows the method used in the country.",
          "طريقة حساب الفجر والعشاء. التلقائي يتبع الطريقة المعتمدة في البلد.")
      )
    case .madhab:
      return (
        "sun.max", copy.text("Asr (madhab)", "العصر (المذهب)"),
        copy.text(
          "Hanafi Asr begins when a shadow is twice its object’s length; the others, when it’s equal.",
          "يبدأ العصر عند الحنفية عندما يصبح الظل ضعفي طول الجسم، وعند غيرهم عندما يساويه.")
      )
    case .highLatitude:
      return (
        "globe.europe.africa", copy.text("High latitudes", "خطوط العرض العليا"),
        copy.text(
          "Bounds Fajr and Isha where twilight lasts all night.",
          "تضبط الفجر والعشاء حيث يستمر الشفق طوال الليل.")
      )
    case .adjustments:
      return (
        "slider.horizontal.3", copy.text("Adjustments", "التعديلات"),
        copy.text(
          "Move a prayer’s time by minutes, to match your mosque.",
          "حرّك وقت صلاة بالدقائق ليوافق مسجدك.")
      )
    case .ramadanIsha:
      return (
        "moon.stars", copy.text("Delay Isha in Ramadan", "تأخير العشاء في رمضان"),
        copy.text(
          "For methods that set Isha by an interval after Maghrib. Ramadan uses 120 minutes; angle-based Isha is unchanged.",
          "للطرق التي تحدد العشاء بفاصل بعد المغرب. يُستخدم فاصل ١٢٠ دقيقة في رمضان؛ ولا يتغير العشاء المحسوب بالزاوية."
        )
      )
    case .adhan:
      return (
        "speaker.wave.2.fill", copy.text("Adhan on this Apple TV", "الأذان على جهاز Apple TV هذا"),
        copy.text(
          "The adhan plays at each prayer while Salah is open. Apple TV can’t play it when Salah is closed.",
          "يُرفع الأذان عند كل صلاة ما دام تطبيق صلاة مفتوحًا. لا يستطيع Apple TV تشغيله وصلاة مغلق.")
      )
    case .prayers:
      return (
        "bell", copy.text("Prayers", "الصلوات"),
        copy.text(
          "Choose the sound for each prayer, or turn one off.",
          "اختر صوت كل صلاة، أو أوقف إحداها.")
      )
    case .dua:
      return (
        "text.quote", copy.text("Du’a after the adhan", "الدعاء بعد الأذان"),
        copy.text(
          "A spoken du’a follows the adhan.", "يُتلى الدعاء بعد الأذان.")
      )
    case .volume:
      return (
        "speaker.3", copy.text("Volume", "مستوى الصوت"),
        copy.text(
          "How loud Salah plays the adhan, under the TV’s own volume.",
          "مستوى صوت الأذان في صلاة، ضمن مستوى صوت التلفاز.")
      )
    case .appearance:
      return (
        "circle.lefthalf.filled", copy.text("Appearance", "المظهر"),
        copy.text(
          "Light, dark, or as this Apple TV is set.", "فاتح أو داكن أو حسب إعداد جهاز Apple TV.")
      )
    case .language:
      return (
        "character.bubble", copy.text("Language", "اللغة"),
        copy.text(
          "The language of Salah’s names, dates and digits.",
          "لغة الأسماء والتواريخ والأرقام في صلاة.")
      )
    case .timeOfDay:
      return (
        "sunrise", copy.text("Sky follows the time of day", "السماء تتبع وقت اليوم"),
        copy.text(
          "Tint the sky from dawn to night, or keep it neutral.",
          "لوّن السماء من الفجر إلى الليل، أو أبقها محايدة.")
      )
    case .hijri:
      return (
        "calendar", copy.text("Hijri date", "التاريخ الهجري"),
        copy.text(
          "Umm al-Qura, moved by up to three days to match a local moon sighting.",
          "أم القرى، مع تحريك حتى ثلاثة أيام ليوافق رؤية الهلال المحلية.")
      )
    case .about:
      return (
        "info.circle", copy.text("About Salah", "عن صلاة"),
        copy.text(
          "The version, the sources of the times and the adhan recordings, and privacy.",
          "الإصدار، ومصادر الأوقات وتسجيلات الأذان، والخصوصية.")
      )
    }
  }
}

/// A Settings switch that says On or Off in Salah's language. tvOS's own toggle takes those
/// words from SwiftUI's strings, which have no Urdu, Persian or Bengali.
struct TVSwitchStyle: ToggleStyle {
  let copy: TVSettingsCopy

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack {
        configuration.label
        Spacer(minLength: 24)
        // VoiceOver reads it as the switch's value, once.
        Text(verbatim: copy.onOff(configuration.isOn))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
    .accessibilityValue(copy.onOff(configuration.isOn))
    .accessibilityAddTraits(.isToggle)
  }
}
