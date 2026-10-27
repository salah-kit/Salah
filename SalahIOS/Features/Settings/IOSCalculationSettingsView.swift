import SalahCalculation
import SalahCore
import SalahTimes
import SwiftUI

struct IOSCalculationSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }
  private let featured: [CalculationMethod] = [
    .moonsightingCommittee, .muslimWorldLeague, .isna, .egyptian, .ummAlQura,
  ]

  var body: some View {
    Form {
      Section(copy.text("Method", "طريقة الحساب")) {
        Toggle(copy.text("Automatic by country", "تلقائي حسب البلد"), isOn: automatic)
          .accessibilityIdentifier("method.automatic")
        ForEach(featured, id: \.self) { method in methodOption(method) }
      }
      Section {
        NavigationLink {
          IOSAllMethodsSettingsView()
        } label: {
          IOSSettingsRow(title: copy.text("All 14 methods", "جميع الطرق الـ ١٤"))
        }
        .accessibilityIdentifier("method.all")
        NavigationLink {
          IOSCustomAnglesSettingsView()
        } label: {
          IOSSettingsRow(title: copy.text("Custom angles", "زوايا مخصصة"))
        }
        .accessibilityIdentifier("method.custom")
      } footer: {
        Text(
          copy.text(
            "Automatic uses a country suggestion when available; otherwise your chosen method stays. You can always choose manually.",
            "يستخدم الوضع التلقائي اقتراح البلد عند توفره؛ وإلا تبقى طريقتك المختارة. يمكنك الاختيار يدويًا دائمًا."
          ))
      }
      Section(copy.text("Asr (madhab)", "العصر (المذهب)")) {
        IOSMadhabOptions()
      }
      Section {
        NavigationLink {
          IOSHighLatitudeSettingsView()
        } label: {
          IOSSettingsRow(
            title: copy.text("Rule", "القاعدة"),
            value: copy.highLatitude(
              store.preferences.automaticHighLatitude
                ? .recommended : store.preferences.highLatitudeRule))
        }
        .accessibilityIdentifier("calculation.highLatitude")
      } header: {
        Text(copy.text("High latitudes", "خطوط العرض العليا"))
      } footer: {
        Text(
          copy.text(
            "Above 48°, Recommended uses the seventh of the night for Fajr and Isha.",
            "بعد خط عرض ٤٨°، يستخدم الخيار الموصى به سُبع الليل للفجر والعشاء."))
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Calculation", "الحساب"))
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("calculation.form")
  }

  private var automatic: Binding<Bool> {
    Binding(
      get: { store.preferences.method == .automatic },
      set: { enabled in
        let selected = store.preferences.resolvedMethod
        store.updatePreferences { $0.method = enabled ? .automatic : .preset(selected) }
      })
  }

  private func methodOption(_ method: CalculationMethod) -> some View {
    IOSSettingsOption(
      title: IOSCalculationMethod.preset(method).title(locale: store.locale),
      detail: IOSMethodSummary(method: method, copy: copy).text,
      selected: store.preferences.method == .preset(method),
      identifier: "method.\(method.rawValue)"
    ) {
      store.updatePreferences { $0.method = .preset(method) }
    }
  }
}

private struct IOSAllMethodsSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  @State private var search = ""
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        ForEach(methods, id: \.self) { method in
          IOSSettingsOption(
            title: IOSCalculationMethod.preset(method).title(locale: store.locale),
            detail: IOSMethodSummary(method: method, copy: copy).text,
            selected: store.preferences.method == .preset(method),
            identifier: "method.\(method.rawValue)"
          ) {
            store.updatePreferences { $0.method = .preset(method) }
          }
        }
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("All methods", "جميع الطرق"))
    .navigationBarTitleDisplayMode(.large)
    .searchable(text: $search, prompt: copy.text("Search methods", "ابحث عن طريقة"))
  }

  private var methods: [CalculationMethod] {
    guard !search.isEmpty else { return CalculationMethod.allCases }
    return CalculationMethod.allCases.filter {
      IOSCalculationMethod.preset($0).title(locale: store.locale)
        .localizedStandardContains(search)
        || IOSCalculationMethod.preset($0).title().localizedStandardContains(search)
    }
  }
}

private struct IOSMethodSummary {
  let method: CalculationMethod
  let copy: IOSSettingsCopy

  var text: String {
    let parameters = method.parameters
    let fajr: String
    switch parameters.fajr {
    case .angle(let angle):
      fajr = copy.format("Fajr %@°", "الفجر %@°", copy.number(angle))
    case .moonsightingCommittee: fajr = copy.text("Fajr 18°", "الفجر ١٨°")
    }
    let isha: String
    switch parameters.isha {
    case .angle(let angle):
      isha = copy.format("Isha %@°", "العشاء %@°", copy.number(angle))
    case .minutesAfterMaghrib(let minutes):
      isha = copy.format(
        "Isha %@ min after Maghrib", "العشاء بعد المغرب بـ %@ د", copy.number(minutes))
    case .moonsightingCommittee:
      isha = copy.text("Isha 18° · seasonal limits", "العشاء ١٨° · حدود موسمية")
    }
    return "\(fajr) · \(isha)"
  }
}

struct IOSMadhabSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section(copy.text("Asr (madhab)", "العصر (المذهب)")) { IOSMadhabOptions() }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Asr (madhab)", "العصر (المذهب)"))
    .navigationBarTitleDisplayMode(.large)
  }
}

private struct IOSMadhabOptions: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    IOSSettingsOption(
      title: copy.text("Shafi’i, Maliki, Hanbali", "شافعي، مالكي، حنبلي"),
      detail: copy.text(
        "Asr when a shadow equals its object’s length", "العصر عندما يساوي الظل طول الجسم"),
      selected: store.preferences.madhab == .shafi, identifier: "asr.shafi"
    ) { store.updatePreferences { $0.madhab = .shafi } }
    IOSSettingsOption(
      title: copy.text("Hanafi", "حنفي"),
      detail: copy.text(
        "Asr when a shadow is twice its object’s length", "العصر عندما يساوي الظل ضعفي طول الجسم"),
      selected: store.preferences.madhab == .hanafi, identifier: "asr.hanafi"
    ) { store.updatePreferences { $0.madhab = .hanafi } }
  }
}

struct IOSHighLatitudeSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        ForEach(HighLatitudeRule.allCases, id: \.self) { rule in
          IOSSettingsOption(
            title: copy.highLatitude(rule), detail: detail(rule), selected: selected == rule,
            identifier: "highLatitude.\(rule.rawValue)"
          ) {
            store.updatePreferences {
              $0.automaticHighLatitude = rule == .recommended
              $0.highLatitudeRule = rule
            }
          }
        }
      } footer: {
        Text(
          copy.text(
            "These rules bound Fajr and Isha where twilight lasts all night. The Moonsighting Committee method uses its own seasonal limits.",
            "تضبط هذه القواعد الفجر والعشاء حيث يستمر الشفق طوال الليل. تستخدم طريقة لجنة رؤية الهلال حدودها الموسمية الخاصة."
          ))
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("High latitudes", "خطوط العرض العليا"))
    .navigationBarTitleDisplayMode(.large)
  }

  private var selected: HighLatitudeRule {
    store.preferences.automaticHighLatitude ? .recommended : store.preferences.highLatitudeRule
  }

  private func detail(_ rule: HighLatitudeRule) -> String {
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

struct IOSCustomAnglesSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        angleRow(.fajr, binding: customAngle(\.customFajrAngle))
        angleRow(.isha, binding: customAngle(\.customIshaAngle))
      } footer: {
        Text(
          copy.text(
            "A custom method uses your Fajr and Isha angles. Asr, high-latitude rules and minute adjustments still apply.",
            "تستخدم الطريقة المخصصة زاويتي الفجر والعشاء اللتين تختارهما. تظل إعدادات العصر وخطوط العرض والتعديلات بالدقائق سارية."
          ))
      }
      Section {
        Text(
          copy.text(
            "Times may differ from your mosque’s timetable. Check your local calculation convention before changing angles.",
            "قد تختلف المواقيت عن جدول مسجدك. تحقق من طريقة الحساب المحلية قبل تغيير الزوايا.")
        )
        .font(.footnote)
        .foregroundStyle(IOSTheme.labelSecondary)
        .listRowBackground(Color.clear)
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Custom angles", "زوايا مخصصة"))
    .navigationBarTitleDisplayMode(.large)
  }

  /// An angle's binding. Changing an angle chooses the custom method; opening the page to
  /// look at the angles leaves the method as it was.
  private func customAngle(_ angle: WritableKeyPath<IOSPreferences, Double>) -> Binding<Double> {
    Binding(
      get: { store.preferences[keyPath: angle] },
      set: { value in
        store.updatePreferences {
          $0[keyPath: angle] = value
          $0.method = .custom
        }
      })
  }

  private func angleRow(_ prayer: PrayerKind, binding: Binding<Double>) -> some View {
    Stepper(value: binding, in: 1...30, step: 0.5) {
      IOSSettingsRow(
        title: copy.prayer(prayer), value: "\(copy.number(binding.wrappedValue))°",
        subtitle: copy.text("Solar angle", "زاوية الشمس"), prayer: prayer)
    }
    .accessibilityIdentifier("customAngle.\(prayer.rawValue)")
    .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
    .accessibilityValue("\(copy.number(binding.wrappedValue))°")
  }
}

struct IOSAdjustmentsSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        ForEach(PrayerKind.allCases, id: \.self) { kind in
          Stepper(value: adjustment(kind), in: -60...60) {
            IOSSettingsRow(
              title: copy.prayer(kind),
              value: copy.signedMinutes(store.preferences.adjustments.settingsMinutes(for: kind)),
              subtitle: adjustmentDetail(kind), prayer: kind)
          }
          .accessibilityIdentifier("adjustment.\(kind.rawValue)")
          .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
          .accessibilityValue(
            copy.signedMinutes(store.preferences.adjustments.settingsMinutes(for: kind)))
        }
      } footer: {
        Text(
          copy.text(
            "Shift a prayer by whole minutes, from −60 to +60. The method’s own minutes stay separate, so changing yours never erases them.",
            "قدّم أو أخّر الصلاة بدقائق كاملة من −٦٠ إلى +٦٠. تبقى دقائق الطريقة منفصلة، فلا يؤدي تعديلك إلى حذفها."
          ))
      }
      IOSHijriSettingsSection()
      if store.preferences.offersDelayedIsha {
        Section {
          Toggle(
            copy.text("Delay Isha in Ramadan", "تأخير العشاء في رمضان"),
            isOn: store.settingsBinding(\.delayedIshaInRamadan)
          )
          .accessibilityIdentifier("adjustment.ramadanIsha")
        } footer: {
          Text(
            copy.text(
              "For methods that set Isha by an interval after Maghrib. Ramadan uses 120 minutes; angle-based Isha is unchanged.",
              "للطرق التي تحدد العشاء بفاصل بعد المغرب. يُستخدم فاصل ١٢٠ دقيقة في رمضان؛ ولا يتغير العشاء المحسوب بالزاوية."
            ))
        }
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Adjustments", "التعديلات"))
    .navigationBarTitleDisplayMode(.large)
  }

  private func adjustment(_ kind: PrayerKind) -> Binding<Int> {
    Binding(
      get: { store.preferences.adjustments.settingsMinutes(for: kind) },
      set: { value in
        store.updatePreferences { $0.adjustments.setSettingsMinutes(value, for: kind) }
      })
  }

  private func adjustmentDetail(_ kind: PrayerKind) -> String {
    let method = store.preferences.calculation.parameters.methodAdjustments.settingsMinutes(
      for: kind)
    let yours = store.preferences.adjustments.settingsMinutes(for: kind)
    if method == 0, yours == 0 { return copy.text("As calculated", "كما حُسبت") }
    return copy.format(
      "Yours %@ · method %@", "تعديلك %@ · الطريقة %@", copy.number(yours),
      (method > 0 ? "+" : "") + copy.number(method))
  }
}

struct IOSHijriSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form { IOSHijriSettingsSection() }
      .iosSettingsForm()
      .navigationTitle(copy.text("Hijri date", "التاريخ الهجري"))
      .navigationBarTitleDisplayMode(.large)
  }
}

private struct IOSHijriSettingsSection: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Section {
      Stepper(value: store.settingsBinding(\.hijriOffset), in: -3...3) {
        IOSSettingsRow(
          title: copy.text("Hijri date offset", "تعديل التاريخ الهجري"), subtitle: dateDescription)
      }
      .accessibilityIdentifier("hijri.offset")
      .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
      .accessibilityValue(copy.number(store.preferences.hijriOffset))
    } header: {
      Text(copy.text("Hijri date", "التاريخ الهجري"))
    } footer: {
      Text(
        copy.text(
          "Add or subtract up to 3 days for your local moon sighting. This also adjusts when Ramadan begins.",
          "أضف أو اطرح حتى ٣ أيام وفق رؤية الهلال المحلية. يضبط هذا أيضًا بداية رمضان."))
    }
  }

  private var dateDescription: String {
    let formatter = DateFormatter()
    var calendar = Calendar(identifier: .islamicUmmAlQura)
    calendar.timeZone = store.timeZone
    formatter.calendar = calendar
    formatter.timeZone = store.timeZone
    formatter.locale = store.locale
    formatter.dateFormat = "d MMMM yyyy"
    let date =
      calendar.date(byAdding: .day, value: store.preferences.hijriOffset, to: store.now)
      ?? store.now
    let offset = store.preferences.hijriOffset
    let description =
      offset == 0
      ? copy.text("no offset", "بلا تعديل")
      : copy.format(
        "%@ days", "%@ أيام", (offset > 0 ? "+" : "") + copy.number(offset))
    return "\(formatter.string(from: date)) · \(description)"
  }
}
