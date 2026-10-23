import SalahCalculation
import SalahCore
import SalahTimes
import SwiftUI
import UIKit

nonisolated enum IOSOnboardingPresentation: Equatable, Sendable {
  case fullScreen, formSheet
}

/// First-run decisions share the production settings and platform services.
/// Native permission requests are made only after their explanation is visible.
struct IOSOnboardingView: View {
  var presentation: IOSOnboardingPresentation = .fullScreen

  @Environment(IOSAppStore.self) private var store
  @Environment(IOSLocationService.self) private var locationService
  @Environment(IOSNotificationService.self) private var notifications
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var methodRowHeight: CGFloat = 66
  @State private var path: [Destination] = []
  @State private var waitingForLocation = false
  @State private var requestingNotifications = false
  @State private var notificationDenied = false
  @State private var showCalculation = false

  private enum Destination: Hashable { case city }

  var body: some View {
    NavigationStack(path: $path) {
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 14) {
            IOSOnboardingArtwork(step: store.onboardingStep, readyKind: nextPrayer?.kind)
              .accessibilityHidden(true)
            Text(title)
              .font(.title.bold())
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("onboarding.title")
            Text(detail)
              .font(.body)
              .foregroundStyle(IOSTheme.labelSecondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("onboarding.detail")
            if store.onboardingStep == .calculation { calculationOptions }
            if waitingForLocation { locationProgress }
            Spacer(minLength: 0)
            pageIndicator
            actions
          }
          .frame(maxWidth: presentation == .formSheet ? 322 : 400)
          .padding(.horizontal, presentation == .formSheet ? 24 : 40)
          .padding(
            .top,
            presentation == .formSheet ? 70 : min(110, max(24, geometry.size.height * 0.142))
          )
          .padding(
            .bottom,
            presentation == .formSheet ? 54 : (store.onboardingStep == .calculation ? 19 : 32)
          )
          .frame(maxWidth: .infinity, minHeight: geometry.size.height)
        }
        .scrollIndicators(.hidden)
      }
      .background {
        IOSSkyBackground(
          phase: .dhuhr, fadeStart: 0.35, fadeEnd: presentation == .formSheet ? 0.8 : 0.75
        ).ignoresSafeArea()
      }
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: Destination.self) { destination in
        switch destination {
        case .city:
          IOSLocationSettingsView {
            // The NavigationStack owns the pop and keyboard transition. Do not put
            // an onboarding animation into the same commit as removing its city page.
            waitingForLocation = false
            store.onboardingStep = .notifications
            path.removeAll()
          }
          .toolbar(.visible, for: .navigationBar)
        }
      }
      .sheet(isPresented: $showCalculation) {
        NavigationStack {
          IOSCalculationSettingsView()
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button(text("Done", "تم"), systemImage: "checkmark") {
                  showCalculation = false
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("onboarding.calculation.done")
              }
            }
        }
      }
      .onChange(of: notifications.status) { _, status in
        // Returning from Settings refreshes the live service in IOSAppRuntime.activate().
        // Recovery must follow that authorization, rather than retain its old local flag.
        guard notificationDenied, status == .authorized else { return }
        notificationDenied = false
        if store.onboardingStep == .notifications { advance(to: .calculation) }
      }
      .onChange(of: locationService.authorizationStatus) { _, status in
        guard waitingForLocation else { return }
        if status == .denied || status == .restricted { chooseCity() }
      }
      .onChange(of: store.preferences.location) { _, location in
        guard waitingForLocation, location != nil else { return }
        waitingForLocation = false
        advance(to: .notifications)
      }
      .onChange(of: locationService.isLocating) { _, isLocating in
        guard waitingForLocation, !isLocating, store.preferences.location != nil,
          locationService.errorMessage == nil
        else { return }
        waitingForLocation = false
        advance(to: .notifications)
      }
    }
    .accessibilityIdentifier(presentation == .formSheet ? "onboarding.formSheet" : "onboarding")
  }

  private var title: String {
    if notificationDenied {
      return text("Notifications are off", "التنبيهات متوقفة")
    }
    switch store.onboardingStep {
    case .welcome: return text("Prayer times, calm and on time", "أوقات الصلاة، بهدوء وفي موعدها")
    case .location: return text("Times for where you are", "أوقات الصلاة في مكانك")
    case .notifications: return text("An alert at each prayer", "تنبيه عند كل صلاة")
    case .calculation: return text("How times are calculated", "طريقة حساب الأوقات")
    case .ready: return text("You’re all set", "كل شيء جاهز")
    }
  }

  private var detail: String {
    if notificationDenied {
      return text(
        "Your prayer alerts are saved. Turn on notifications in Settings to receive them. Focus and Scheduled Summary may delay delivery.",
        "تم حفظ تنبيهات الصلاة. فعّل التنبيهات من الإعدادات لاستلامها. قد يؤخر التركيز والملخص المجدول وصولها."
      )
    }
    switch store.onboardingStep {
    case .welcome:
      return text(
        "Salah shows today’s prayers, counts down to the next, and reminds you when it’s time.",
        "يعرض تطبيق صلاة أوقات الصلاة والوقت المتبقي للصلاة القادمة، ويذكّرك عند دخول وقتها.")
    case .location:
      return text(
        "Salah uses your location for prayer times and Qibla. Apple helps find your city and time zone.",
        "يستخدم تطبيق صلاة موقعك لأوقات الصلاة واتجاه القبلة. تساعد Apple في تحديد مدينتك ومنطقتها الزمنية."
      )
    case .notifications:
      return text(
        "Choose prayers, alert sounds and reminders. Notifications play a short clip; open Salah for the full adhan.",
        "اختر الصلوات وأصوات التنبيهات والتذكيرات. تُشغّل الإشعارات مقطعًا قصيرًا؛ افتح تطبيق صلاة لسماع الأذان كاملًا."
      )
    case .calculation: return calculationDetail
    case .ready: return readyDetail
    }
  }

  private var pageIndicator: some View {
    HStack(spacing: 8) {
      ForEach(IOSOnboardingStep.allCases, id: \.rawValue) { step in
        Circle()
          .fill(step == store.onboardingStep ? IOSTheme.labelPrimary : IOSTheme.labelQuaternary)
          .frame(width: 7, height: 7)
      }
    }
    .frame(height: 7)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(
        format: text("Step %lld of %lld", "الخطوة %lld من %lld"),
        locale: store.locale,
        Int64(store.onboardingStep.rawValue + 1), Int64(IOSOnboardingStep.allCases.count))
    )
    .accessibilityIdentifier("onboarding.progress")
  }

  @ViewBuilder private var actions: some View {
    VStack(spacing: 4) {
      if notificationDenied {
        primary(text("Open Settings", "فتح الإعدادات"), id: "onboarding.notification.openSettings")
        {
          openNotificationSettings()
        }
        secondary(
          text("Continue without notifications", "المتابعة دون تنبيهات"),
          id: "onboarding.notification.continueWithout"
        ) {
          notificationDenied = false
          advance(to: .calculation)
        }
      } else {
        switch store.onboardingStep {
        case .welcome:
          primary(text("Continue", "متابعة"), id: "onboarding.continue") {
            advance(to: .location)
          }
        case .location:
          primary(
            text("Allow Location Access", "السماح بالوصول إلى الموقع"),
            id: "onboarding.location.allow", disabled: locationService.isLocating
          ) {
            waitingForLocation = true
            store.updatePreferences { $0.useCurrentLocation = true }
            locationService.requestLocation()
            if locationService.authorizationStatus == .denied
              || locationService.authorizationStatus == .restricted
            {
              chooseCity()
            }
          }
          secondary(text("Choose a City", "اختيار مدينة"), id: "onboarding.location.chooseCity") {
            chooseCity()
          }
        case .notifications:
          primary(
            text("Allow Notifications", "السماح بالتنبيهات"),
            id: "onboarding.notification.allow", disabled: requestingNotifications
          ) { requestNotifications() }
          secondary(text("Not Now", "ليس الآن"), id: "onboarding.notification.notNow") {
            advance(to: .calculation)
          }
        case .calculation:
          primary(text("Continue", "متابعة"), id: "onboarding.calculation.continue") {
            advance(to: .ready)
          }
        case .ready:
          primary(text("Start", "ابدأ"), id: "onboarding.ready.start") {
            store.completeOnboarding()
          }
        }
      }
    }
  }

  private func primary(
    _ label: String, id: String, disabled: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(label)
        .font(.body.weight(.medium))
        .foregroundStyle(IOSTheme.labelOnAccent)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.glassProminent)
    .controlSize(.large)
    .tint(IOSTheme.accentFill)
    .disabled(disabled)
    .accessibilityIdentifier(id)
  }

  private func secondary(_ label: String, id: String, action: @escaping () -> Void) -> some View {
    Button(label, action: action)
      .font(.body)
      .buttonStyle(.plain)
      .foregroundStyle(IOSTheme.accentText)
      .frame(minHeight: 50)
      .accessibilityIdentifier(id)
  }

  private var locationProgress: some View {
    VStack(spacing: 8) {
      if locationService.isLocating {
        ProgressView(text("Finding your location…", "جارٍ تحديد موقعك…"))
      } else if locationService.errorMessage != nil {
        Label(
          text(
            "Could not get your location. Try again or choose a city.",
            "تعذر تحديد موقعك. حاول مجددًا أو اختر مدينة."),
          systemImage: "location.slash"
        )
        .foregroundStyle(IOSTheme.labelSecondary)
      }
    }
    .font(.footnote)
    .multilineTextAlignment(.center)
    .accessibilityIdentifier("onboarding.location.status")
  }

  private func advance(to step: IOSOnboardingStep) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
      store.onboardingStep = step
    }
  }

  private func chooseCity() {
    waitingForLocation = false
    locationService.cancelLocation()
    store.updatePreferences { $0.useCurrentLocation = false }
    if path.last != .city { path.append(.city) }
  }

  private func requestNotifications() {
    requestingNotifications = true
    Task {
      let status = await notifications.requestAuthorization()
      requestingNotifications = false
      if status == .authorized {
        advance(to: .calculation)
      } else {
        notificationDenied = true
      }
    }
  }

  private func openNotificationSettings() {
    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
    Task { _ = await UIApplication.shared.open(url) }
  }

  private func text(_ english: String, _ arabic: String) -> String {
    IOSL10n.text(english, arabic: arabic, locale: store.locale)
  }
}

extension IOSOnboardingView {
  private var suggestedMethod: CalculationMethod? {
    store.preferences.location.flatMap { CalculationMethod.suggested(for: $0) }
  }

  private var quickMethods: [IOSCalculationMethod] {
    let suggested = suggestedMethod ?? .muslimWorldLeague
    let first = IOSCalculationMethod.preset(suggested)
    switch store.preferences.method {
    case .custom: return [.custom, first]
    case .preset(let selected) where selected != suggested: return [.preset(selected), first]
    default:
      let second: CalculationMethod = suggested == .muslimWorldLeague ? .isna : .muslimWorldLeague
      return [first, .preset(second)]
    }
  }

  private func isSelected(_ method: IOSCalculationMethod) -> Bool {
    if method == .custom { return store.preferences.method == .custom }
    guard case .preset(let preset) = method, store.preferences.method != .custom else {
      return false
    }
    return store.preferences.resolvedMethod == preset
  }

  private func methodIdentifier(_ method: IOSCalculationMethod) -> String {
    switch method {
    case .automatic: "automatic"
    case .custom: "custom"
    case .preset(let value): value.rawValue
    }
  }

  private var calculationDetail: String {
    guard let method = suggestedMethod else {
      return text(
        "Choose a calculation method. You can change the method, the madhab for Asr and minute adjustments anytime.",
        "اختر طريقة الحساب. يمكنك تغيير الطريقة ومذهب حساب العصر وتعديل الدقائق في أي وقت.")
    }
    let name =
      method == .ummAlQura
      ? text("Umm al-Qura", "أم القرى")
      : IOSCalculationMethod.preset(method).title(locale: store.locale)
    let country = store.preferences.location?.countryCode.flatMap {
      store.locale.localizedString(forRegionCode: $0)
    }
    if let country {
      return String(
        format: text(
          "For %@, %@ is suggested. You can change the method, the madhab for Asr and minute adjustments anytime.",
          "تُقترح طريقة %@ لـ%@. يمكنك تغيير الطريقة ومذهب حساب العصر وتعديل الدقائق في أي وقت."),
        locale: store.locale,
        store.isArabic ? name : country, store.isArabic ? country : name)
    }
    return String(
      format: text(
        "%@ is suggested for your location. You can change the method, the madhab for Asr and minute adjustments anytime.",
        "تُقترح طريقة %@ لموقعك. يمكنك تغيير الطريقة ومذهب حساب العصر وتعديل الدقائق في أي وقت."),
      locale: store.locale, name)
  }

  private var calculationOptions: some View {
    VStack(spacing: 8) {
      List {
        ForEach(quickMethods, id: \.self) { method in
          Button {
            store.updatePreferences { $0.method = method }
          } label: {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                  HStack(spacing: 8) {
                    Text(method.title(locale: store.locale))
                    if method == suggestedMethod.map(IOSCalculationMethod.preset) { suggestedBadge }
                  }
                  VStack(alignment: .leading, spacing: 3) {
                    Text(method.title(locale: store.locale))
                    if method == suggestedMethod.map(IOSCalculationMethod.preset) { suggestedBadge }
                  }
                }
                Text(methodDetail(method))
                  .font(.footnote)
                  .foregroundStyle(IOSTheme.labelSecondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              if isSelected(method) {
                Image(systemName: "checkmark")
                  .foregroundStyle(IOSTheme.accentText)
                  .accessibilityHidden(true)
              }
            }
            .foregroundStyle(IOSTheme.labelPrimary)
            .font(.body)
          }
          .accessibilityAddTraits(
            isSelected(method) ? [.isSelected] : []
          )
          .contextMenu {
            Button(text("All methods and adjustments", "كل الطرق والتعديلات")) {
              showCalculation = true
            }
          }
          .accessibilityAction(named: text("All methods and adjustments", "كل الطرق والتعديلات")) {
            showCalculation = true
          }
          .accessibilityIdentifier("onboarding.calculation.\(methodIdentifier(method))")
        }
      }
      .listStyle(.plain)
      .scrollDisabled(true)
      .scrollContentBackground(.hidden)
      .clipShape(.rect(cornerRadius: 20))
      .frame(height: methodListHeight)
    }
  }

  private var methodListHeight: CGFloat {
    // Two native selection rows gain room for stacked title/badge and wrapped details at AX sizes.
    max(132, methodRowHeight * (typeSize.isAccessibilitySize ? 3 : 2))
  }

  private var suggestedBadge: some View {
    Text(text("Suggested", "مقترحة"))
      .font(.caption2.weight(.semibold))
      .foregroundStyle(IOSTheme.accentText)
      .padding(.horizontal, 7)
      .padding(.vertical, 1)
      .background(IOSTheme.accentSubtle, in: Capsule())
  }

  private func methodDetail(_ method: IOSCalculationMethod) -> String {
    let parameters: CalculationParameters
    switch method {
    case .preset(let value): parameters = value.parameters
    case .automatic, .custom: parameters = store.preferences.calculation.parameters
    }
    let fajr: String
    switch parameters.fajr {
    case .angle(let degrees):
      fajr = String(format: text("Fajr %@°", "الفجر %@°"), number(degrees))
    case .moonsightingCommittee:
      fajr = text("Seasonal Fajr", "الفجر الموسمي")
    }
    let isha: String
    switch parameters.isha {
    case .angle(let degrees):
      isha = String(format: text("Isha %@°", "العشاء %@°"), number(degrees))
    case .minutesAfterMaghrib(let minutes):
      isha = String(
        format: text("Isha %@ min after Maghrib", "العشاء بعد المغرب بـ%@ دقيقة"),
        number(Double(minutes)))
    case .moonsightingCommittee:
      isha = text("Seasonal Isha", "العشاء الموسمي")
    }
    return "\(fajr) · \(isha)"
  }

  private func number(_ value: Double) -> String {
    value.formatted(.number.locale(store.locale).precision(.fractionLength(0...1)))
  }

  private var nextPrayer: PrayerEvent? { store.display?.prayerState?.nextPrayer }

  private var readyDetail: String {
    guard let event = nextPrayer, let display = store.display else {
      return text(
        "Your settings are saved. Open Salah to see the times available for your location.",
        "تم حفظ إعداداتك. افتح تطبيق صلاة للاطلاع على الأوقات المتاحة لموقعك.")
    }
    let interval = max(0, event.time.timeIntervalSince(store.now))
    let formatter = DateComponentsFormatter()
    formatter.calendar = {
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = store.locale
      calendar.timeZone = store.timeZone
      return calendar
    }()
    formatter.unitsStyle = .full
    formatter.allowedUnits = interval >= 3_600 ? [.hour, .minute] : [.minute]
    formatter.maximumUnitCount = 2
    let duration = formatter.string(from: max(60, interval)) ?? number(1)
    return String(
      format: text("Next prayer: %@ at %@, in %@.", "الصلاة القادمة: %@ الساعة %@، بعد %@."),
      locale: store.locale, display.name(of: event), display.timeText(of: event), duration)
  }
}
