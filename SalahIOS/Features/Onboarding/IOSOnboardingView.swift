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
///
/// Each step is a page pushed on one navigation stack, so Back and the edge swipe return to
/// the step before with its choice as it was left.
struct IOSOnboardingView: View {
  var presentation: IOSOnboardingPresentation = .fullScreen

  @Environment(IOSAppStore.self) private var store
  @Environment(IOSLocationService.self) private var locationService
  @Environment(IOSNotificationService.self) private var notifications
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var methodRowHeight: CGFloat = 66
  @State private var path: [Route] = []
  @State private var waitingForLocation = false
  @State private var requestingNotifications = false
  @State private var notificationDenied = false
  @State private var showCalculation = false
  @State private var alertMode = IOSAlertMode.notification

  private enum Route: Hashable {
    case step(IOSOnboardingStep)
    case city
  }

  /// The step on screen: the last one pushed, or Welcome at the root.
  private var current: IOSOnboardingStep {
    for route in path.reversed() {
      if case .step(let step) = route { return step }
    }
    return .welcome
  }

  var body: some View {
    NavigationStack(path: $path) {
      page(.welcome)
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .step(let step): page(step)
          case .city:
            IOSLocationSettingsView {
              // One change replaces the city page with the next step, so Back from there
              // returns to Location.
              waitingForLocation = false
              path = [.step(.location), .step(.notifications)]
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
        .onChange(of: path) { store.onboardingStep = current }
        .onChange(of: notifications.status) { _, status in
          // Returning from Settings refreshes the live service in IOSAppRuntime.activate().
          // Recovery must follow that authorization, rather than retain its old local flag.
          guard notificationDenied, status == .authorized else { return }
          notificationDenied = false
          if current == .notifications { advance(to: .reminders) }
        }
        .onChange(of: locationService.authorizationStatus) { _, status in
          guard waitingForLocation else { return }
          if status == .denied || status == .restricted { chooseCity() }
        }
        .onChange(of: store.preferences.location) { _, location in
          guard waitingForLocation, location != nil else { return }
          waitingForLocation = false
          if current == .location { advance(to: .notifications) }
        }
        .onChange(of: locationService.isLocating) { _, isLocating in
          guard waitingForLocation, !isLocating, store.preferences.location != nil,
            locationService.errorMessage == nil
          else { return }
          waitingForLocation = false
          if current == .location { advance(to: .notifications) }
        }
    }
    .accessibilityIdentifier(presentation == .formSheet ? "onboarding.formSheet" : "onboarding")
  }

  private func page(_ step: IOSOnboardingStep) -> some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 14) {
          IOSOnboardingArtwork(step: step, readyKind: nextPrayer?.kind)
            .accessibilityHidden(true)
          Text(title(step))
            .font(.title.bold())
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("onboarding.title")
          Text(detail(step))
            .font(.body)
            .foregroundStyle(IOSTheme.labelSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("onboarding.detail")
          switch step {
          case .notifications where !notificationDenied: alertModes
          case .reminders: reminderKinds
          case .calculation: calculationOptions
          case .location where waitingForLocation: locationProgress
          default: EmptyView()
          }
        }
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding(step, height: geometry.size.height))
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
    }
    // On the page, not the bar: it would replace the identifiers of the bar's controls.
    .accessibilityIdentifier("onboarding.step." + String(describing: step))
    // The step's action stays on screen however large the text: the page scrolls above it.
    .safeAreaBar(edge: .bottom) {
      VStack(spacing: 14) {
        pageIndicator(step)
        actions(step)
      }
      .frame(maxWidth: contentWidth)
      .padding(.horizontal, horizontalPadding)
      .padding(.top, 8)
      .padding(.bottom, presentation == .formSheet ? 54 : (step.hasOptions ? 19 : 32))
      .frame(maxWidth: .infinity)
      // The page scrolls under the bar: it fades out above the dots, rather than run into them.
      .background {
        LinearGradient(
          stops: [
            .init(color: IOSTheme.groupedBackground.opacity(0), location: 0),
            .init(color: IOSTheme.groupedBackground, location: 0.18),
          ], startPoint: .top, endPoint: .bottom
        )
        .padding(.top, -24)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
      }
    }
    .background {
      IOSSkyBackground(
        phase: .dhuhr, fadeStart: 0.35, fadeEnd: presentation == .formSheet ? 0.8 : 0.75
      ).ignoresSafeArea()
    }
    // The bar holds only Back; Welcome has nothing to go back to.
    .toolbar(step == .welcome ? .hidden : .visible, for: .navigationBar)
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var contentWidth: CGFloat { presentation == .formSheet ? 322 : 400 }
  private var horizontalPadding: CGFloat { presentation == .formSheet ? 24 : 40 }

  /// The space the hidden bar left is the bar's own on the later steps.
  private func topPadding(_ step: IOSOnboardingStep, height: CGFloat) -> CGFloat {
    if presentation == .formSheet { return step == .welcome ? 70 : 26 }
    let padding = min(110, max(24, height * 0.142))
    return step == .welcome ? padding : max(8, padding - 44)
  }

  private func title(_ step: IOSOnboardingStep) -> String {
    if step == .notifications, notificationDenied {
      return text("Notifications are off", "الإشعارات متوقفة")
    }
    switch step {
    case .welcome: return text("Prayer times, calm and on time", "مواقيت الصلاة بدقة وهدوء")
    case .location: return text("Times for where you are", "مواقيت الصلاة حيثما كنت")
    case .notifications:
      return text("How should Salah alert you?", "كيف تريد أن ينبّهك تطبيق صلاة؟")
    case .reminders: return text("Reminders before and after", "تذكير قبل الصلاة وبعدها")
    case .calculation: return text("How times are calculated", "طريقة حساب المواقيت")
    case .ready: return text("You’re all set", "كل شيء جاهز")
    }
  }

  private func detail(_ step: IOSOnboardingStep) -> String {
    if step == .notifications, notificationDenied {
      return text(
        "Your prayer alerts are saved. Turn on notifications in Settings to receive them. Focus and Scheduled Summary may delay delivery.",
        "حُفظت تنبيهات الصلاة. فعّل الإشعارات من الإعدادات لتصلك. قد يؤخّر «التركيز» و«الملخص المجدول» وصولها."
      )
    }
    switch step {
    case .welcome:
      return text(
        "Salah shows today’s prayers, counts down to the next, and reminds you when it’s time.",
        "يعرض تطبيق صلاة مواقيت الصلاة والوقت المتبقي للصلاة القادمة، ويذكّرك عند دخول وقتها.")
    case .location:
      return text(
        "Salah uses your location for prayer times and Qibla. Apple helps find your city and time zone.",
        "يستخدم تطبيق صلاة موقعك لمواقيت الصلاة واتجاه القبلة. تساعد Apple في تحديد مدينتك ومنطقتها الزمنية."
      )
    case .notifications:
      return text(
        "Choose what happens at prayer time. You can change it anytime in Settings.",
        "اختر ما يحدث عند دخول وقت الصلاة. يمكنك تغييره في أي وقت من الإعدادات.")
    case .reminders:
      return text(
        "Each prayer can also remind you before it begins and after it.",
        "إلى جانب التنبيه عند دخول الوقت، يمكن لكل صلاة أن تذكّرك قبلها وبعدها، ولكلٍّ صوته.")
    case .calculation: return calculationDetail
    case .ready: return readyDetail
    }
  }

  private func pageIndicator(_ current: IOSOnboardingStep) -> some View {
    HStack(spacing: 8) {
      ForEach(IOSOnboardingStep.allCases, id: \.rawValue) { step in
        Circle()
          .fill(step == current ? IOSTheme.labelPrimary : IOSTheme.labelQuaternary)
          .frame(width: 7, height: 7)
      }
    }
    .frame(height: 7)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(
        format: text("Step %lld of %lld", "الخطوة %lld من %lld"),
        locale: store.locale,
        Int64(current.rawValue + 1), Int64(IOSOnboardingStep.allCases.count))
    )
    .accessibilityIdentifier("onboarding.progress")
  }

  @ViewBuilder private func actions(_ step: IOSOnboardingStep) -> some View {
    VStack(spacing: 4) {
      switch step {
      case .welcome:
        primary(text("Continue", "متابعة"), id: "onboarding.continue") {
          advance(to: .location)
        }
      case .location where store.preferences.location != nil && !waitingForLocation:
        // Back from a later step: the place chosen before is kept, and goes on from here.
        primary(text("Continue", "متابعة"), id: "onboarding.location.continue") {
          advance(to: .notifications)
        }
        secondary(text("Choose a City", "اختيار مدينة"), id: "onboarding.location.chooseCity") {
          chooseCity()
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
      case .notifications where notificationDenied:
        primary(text("Open Settings", "فتح الإعدادات"), id: "onboarding.notification.openSettings")
        {
          openNotificationSettings()
        }
        secondary(
          text("Continue without notifications", "المتابعة دون إشعارات"),
          id: "onboarding.notification.continueWithout"
        ) {
          notificationDenied = false
          advance(to: .reminders)
        }
      case .notifications where alertMode == .silent:
        // Silent sends nothing, so it asks for no permission.
        primary(text("Continue", "متابعة"), id: "onboarding.notification.continue") {
          store.updatePreferences { $0.apply(alertMode) }
          advance(to: .reminders)
        }
      case .notifications:
        primary(
          text("Allow Notifications", "السماح بالإشعارات"),
          id: "onboarding.notification.allow", disabled: requestingNotifications
        ) { requestNotifications() }
      case .reminders:
        primary(text("Continue", "متابعة"), id: "onboarding.reminders.continue") {
          advance(to: .calculation)
        }
      case .calculation:
        primary(text("Continue", "متابعة"), id: "onboarding.calculation.continue") {
          advance(to: .ready)
        }
      case .ready:
        primary(text("Start", "ابدأ"), id: "onboarding.ready.start") {
          store.completeOnboarding()
          // Without a place there's nothing to start with: back to choosing one.
          if store.needsOnboarding { path = [.step(.location)] }
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

  /// Pushes the next step. A step already on the stack, reached again after Back, is not
  /// pushed twice.
  private func advance(to step: IOSOnboardingStep) {
    guard current != step else { return }
    path.append(.step(step))
  }

  private func chooseCity() {
    waitingForLocation = false
    locationService.cancelLocation()
    store.updatePreferences { $0.useCurrentLocation = false }
    if path.last != .city { path.append(.city) }
  }

  private func requestNotifications() {
    requestingNotifications = true
    store.updatePreferences { $0.apply(alertMode) }
    Task {
      let status = await notifications.requestAuthorization()
      requestingNotifications = false
      if status == .authorized {
        if current == .notifications { advance(to: .reminders) }
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
          "الطريقة المقترحة في %@ هي %@. يمكنك تغيير الطريقة ومذهب حساب العصر وتعديل الدقائق في أي وقت."
        ),
        locale: store.locale, country, name)
    }
    return String(
      format: text(
        "%@ is suggested for your location. You can change the method, the madhab for Asr and minute adjustments anytime.",
        "الطريقة المقترحة لموقعك هي %@. يمكنك تغيير الطريقة ومذهب حساب العصر وتعديل الدقائق في أي وقت."
      ),
      locale: store.locale, name)
  }

  /// What happens at prayer time. Notification is chosen until the person picks another.
  private var alertModes: some View {
    optionCard {
      ForEach(IOSAlertMode.allCases, id: \.self) { mode in
        Button {
          alertMode = mode
        } label: {
          optionRow(
            symbol: mode.symbol, title: alertTitle(mode), detail: alertDetail(mode),
            selected: alertMode == mode)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(alertMode == mode ? [.isSelected] : [])
        .accessibilityIdentifier("onboarding.notification.\(mode.rawValue)")
        if mode != IOSAlertMode.allCases.last { Divider().padding(.leading, 52) }
      }
    }
  }

  private func alertTitle(_ mode: IOSAlertMode) -> String {
    switch mode {
    case .adhan: text("Adhan", "الأذان")
    case .notification: text("Notification", "الإشعار")
    case .silent: text("Silent", "صامت")
    }
  }

  private func alertDetail(_ mode: IOSAlertMode) -> String {
    switch mode {
    case .adhan:
      text("A short adhan clip plays with each alert", "يُشغَّل مقطع قصير من الأذان مع كل تنبيه")
    case .notification: text("The usual alert sound, no adhan", "صوت التنبيه المعتاد، دون أذان")
    case .silent:
      text("No alerts. Check the times in Salah.", "دون تنبيهات. اطّلع على المواقيت في تطبيق صلاة.")
    }
  }

  /// The three moments a prayer can alert at. Nothing here is chosen: Settings has the controls.
  private var reminderKinds: some View {
    VStack(spacing: 10) {
      optionCard {
        optionRow(
          symbol: "alarm", title: text("Before the prayer", "قبل الصلاة"),
          detail: text("A reminder minutes before it begins", "تذكير قبل دخول الوقت بدقائق"))
        Divider().padding(.leading, 52)
        optionRow(
          symbol: "bell.fill", title: text("At prayer time", "عند دخول الوقت"),
          detail: text("The alert you just chose", "التنبيه الذي اخترته للتو"))
        Divider().padding(.leading, 52)
        optionRow(
          symbol: "bell.badge.fill", title: text("After the prayer", "بعد الصلاة"),
          detail: text("A reminder minutes after it begins", "تذكير بعد دخول الوقت بدقائق"))
      }
      .accessibilityIdentifier("onboarding.reminders.kinds")
      Text(
        text(
          "Set them for each prayer in Settings › Prayer Alerts.",
          "اضبطها لكل صلاة من «تنبيهات الصلاة» في الإعدادات.")
      )
      .font(.footnote)
      .foregroundStyle(IOSTheme.labelSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func optionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
      .background(IOSTheme.groupedSecondary, in: .rect(cornerRadius: 20))
  }

  private func optionRow(symbol: String, title: String, detail: String, selected: Bool = false)
    -> some View
  {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 20))
        .foregroundStyle(IOSTheme.accent)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.body).foregroundStyle(IOSTheme.labelPrimary)
        Text(detail).font(.footnote).foregroundStyle(IOSTheme.labelSecondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      if selected {
        Image(systemName: "checkmark")
          .foregroundStyle(IOSTheme.accentText)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(minHeight: 64)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
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
          .accessibilityIdentifier("onboarding.calculation.\(methodIdentifier(method))")
        }
        Button {
          showCalculation = true
        } label: {
          HStack {
            Text(text("All methods and adjustments", "كل الطرق والتعديلات"))
              .font(.body)
              .foregroundStyle(IOSTheme.labelPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.forward")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(IOSTheme.labelTertiary)
              .accessibilityHidden(true)
          }
        }
        .accessibilityIdentifier("onboarding.calculation.all")
      }
      .listStyle(.plain)
      .scrollDisabled(true)
      .scrollContentBackground(.hidden)
      .clipShape(.rect(cornerRadius: 20))
      .frame(height: methodListHeight)
    }
  }

  private var methodListHeight: CGFloat {
    // Two selection rows gain room for stacked title/badge and wrapped details at AX sizes;
    // the row that opens every method is one line.
    max(132, methodRowHeight * (typeSize.isAccessibilitySize ? 3 : 2))
      + max(48, methodRowHeight * 0.75)
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
        "حُفظت إعداداتك. افتح تطبيق صلاة لعرض المواقيت المتاحة لموقعك.")
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
