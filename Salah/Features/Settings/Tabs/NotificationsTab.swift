import AppKit
import SalahCore
import SwiftUI
import UserNotifications

/// Settings → Notifications: the sound of every alert, then, for the prayer the picker
/// selects, its alert at the prayer's time and its reminders before and after. Jumu'ah has
/// alerts of its own only while Friday's differ from Dhuhr's.
struct NotificationsContent: View {
  @Bindable var prefs = Preferences.shared
  @State private var target: NotificationTarget = .prayer(.fajr)
  @State private var previewController = AudioPlaybackController()
  @State private var notificationSettings: UNNotificationSettings?
  @State private var permissionRequestInFlight = false
  @State private var permissionRequestFailed = false

  private var authorizationStatus: UNAuthorizationStatus? {
    notificationSettings?.authorizationStatus
  }

  /// The prayer the selected target's previews and alerts belong to: Dhuhr for Jumu'ah.
  private var selectedPrayer: PrayerKind {
    if case .prayer(let kind) = target { return kind }
    return .dhuhr
  }

  /// The selected target's alerts. Jumu'ah's are its own; the pane shows them only while
  /// Friday's alerts differ.
  private var config: Binding<PrayerNotificationConfig> {
    Binding(
      get: { target.config(in: prefs) ?? prefs.config(for: selectedPrayer) },
      set: { updated in
        // A preview whose alert is turned off stops with it.
        for slot in [PrayerNotificationSoundSlot.alert, .preReminder, .postReminder]
        where isPreviewing(slot: slot) && !updated.isEnabled(slot) {
          previewController.stop()
        }
        target.setConfig(updated, in: prefs)
      }
    )
  }

  /// Whether the selected target has alerts to edit: every prayer does; Jumu'ah only while
  /// Friday's alerts differ.
  private var editsAlerts: Bool {
    target != .jumuah || prefs.jumuahOverrideEnabled
  }

  private var volume: Binding<Double> {
    Binding(
      get: { Double(prefs.alertVolume) },
      set: { prefs.alertVolume = Int($0.rounded()) }
    )
  }

  var body: some View {
    Section("settings.notif.section.sound") {
      Toggle("settings.notif.silent", isOn: $prefs.silentMode)
      Toggle("settings.notif.duaAfterAdhan", isOn: $prefs.duaEnabled)
        .disabled(prefs.silentMode)
      LabeledContent("settings.notif.volume") {
        Slider(value: volume, in: 0...100, step: 1)
          .labelsHidden()
          .accessibilityLabel(
            Text(verbatim: localizedString("settings.notif.volume", locale: .app))
          )
          .accessibilityValue(
            Text(
              verbatim: (Double(prefs.alertVolume) / 100).formatted(
                .percent.locale(Locale.app)))
          )
          .frame(maxWidth: 164)
          .disabled(prefs.silentMode)
      }
    }
    .onChange(of: prefs.silentMode) {
      // Refresh (audio + display) is emitted by the `silentMode` didSet; this
      // only stops a running in-Settings preview.
      if prefs.silentMode {
        previewController.stop()
      }
    }
    .onChange(of: prefs.alertVolume) {
      previewController.setVolume(Float(prefs.alertVolume) / 100.0)
    }
    // On the one section that's always there, so each fires once whatever the pane shows.
    .onChange(of: prefs.notificationSettings) {
      // The `notificationSettings` didSet emits the reschedule + republish; here
      // we only (re)request authorization if a newly-enabled alert needs it.
      Task {
        await requestAuthorizationIfNeeded()
      }
    }
    .onChange(of: prefs.jumuahOverrideEnabled) {
      Task { await requestAuthorizationIfNeeded() }
    }
    .task {
      await requestAuthorizationIfNeeded()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)
    ) { _ in
      Task {
        await refreshAuthorizationStatus(rescheduleOnGrant: true)
      }
    }

    // One section always follows Sound, so the picker in its header keeps its place (and
    // its focus) whichever prayer it selects: Jumu'ah's Friday switch, or a prayer's alert.
    Section {
      if target == .jumuah {
        Toggle(
          "settings.notif.differentOnFriday",
          isOn: Binding(
            get: { prefs.jumuahOverrideEnabled },
            set: {
              previewController.stop()
              prefs.jumuahOverrideEnabled = $0
            }))
      } else {
        alertRows
      }
    } header: {
      // The picker stands on the window above the first group it edits, not in a group.
      VStack(alignment: .leading, spacing: 18) {
        prayerPicker
        if target != .jumuah {
          Text("settings.notif.section.atPrayerTime")
        }
      }
      .padding(.bottom, target == .jumuah ? 12 : 0)
    } footer: {
      if target == .jumuah {
        Text("settings.notif.differentOnFriday.footer")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }

    if target == .jumuah, prefs.jumuahOverrideEnabled {
      Section("settings.notif.section.atPrayerTime") {
        alertRows
      }
    }

    if editsAlerts {
      Section("settings.notif.section.before") {
        Toggle("settings.notif.remindBefore", isOn: config.preReminderEnabled)
        if config.preReminderEnabled.wrappedValue {
          minutesRow("settings.notif.minutesBefore", value: config.preReminderOffset)
          soundRow(config.preReminderSound, slot: .preReminder)
        }
      }

      Section("settings.notif.section.after") {
        Toggle("settings.notif.remindAfter", isOn: config.postReminderEnabled)
        if config.postReminderEnabled.wrappedValue {
          minutesRow("settings.notif.minutesAfter", value: config.postReminderOffset)
          soundRow(config.postReminderSound, slot: .postReminder)
        }
      }
    }

    Section {
      LabeledContent {
        Button("settings.notif.systemSettings.open") {
          openNotificationSettings()
        }
      } label: {
        Text("settings.notif.systemSettings")
        if let permissionMessage {
          Label {
            Text(localizedString(permissionMessage, locale: .app))
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
          }
        }
      }
    }
  }

  /// The five prayers, Sunrise and Jumu'ah. A target with every alert off shows a muted
  /// bell.
  private var prayerPicker: some View {
    let names = PrayerNames(locale: .app)
    // A preview stops with any change of prayer: a click, an arrow key or VoiceOver.
    return PrayerPicker(
      selection: Binding(
        get: { target },
        set: {
          guard $0 != target else { return }
          previewController.stop()
          target = $0
        }),
      segments: NotificationTarget.all.map { ($0, $0.name(names), $0.isMuted(in: prefs)) }
    )
    // A header is inset like its title; the picker spans the groups' full width.
    .padding(.horizontal, -10)
  }

  /// The alert at the prayer's time, and its sound while it's on. Sunrise, which has no
  /// adhan, says only that it plays at its time.
  @ViewBuilder
  private var alertRows: some View {
    Toggle(
      selectedPrayer == .sunrise && target != .jumuah
        ? "settings.notif.alert.toggle" : "settings.notif.playAdhan",
      isOn: config.alertEnabled)
    if config.alertEnabled.wrappedValue {
      soundRow(config.alertSound, slot: .alert)
    }
  }

  /// A reminder's offset: its minutes, and a stepper from 1 to 120.
  private func minutesRow(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        Text(verbatim: MenuDuration.lead(minutes: value.wrappedValue, locale: .app))
          .monospacedDigit()
        Stepper(title, value: value, in: 1...120)
          .labelsHidden()
      }
    }
  }

  private func soundRow(_ sound: Binding<AdhanSound>, slot: PrayerNotificationSoundSlot)
    -> some View
  {
    SoundPickerRow(
      sound: sound,
      isPreviewing: isPreviewing(slot: slot),
      isSilentMode: prefs.silentMode,
      onPreviewToggle: { togglePreview(sound: sound.wrappedValue, slot: slot) },
      onSoundChanged: { stopPreviewIfNeeded(slot: slot) }
    )
  }

  private var permissionMessage: String.LocalizationValue? {
    if permissionRequestFailed {
      return "settings.notif.permission.error"
    }

    guard let settings = notificationSettings else { return nil }

    switch settings.authorizationStatus {
    case .denied:
      return "settings.notif.permission.denied"

    case .notDetermined:
      return nil

    case .authorized, .provisional:
      if settings.alertSetting == .disabled || settings.notificationCenterSetting == .disabled {
        return "settings.notif.permission.unknown"
      }

      if hasSystemSoundNotifications && settings.soundSetting == .disabled {
        return "settings.notif.permission.unknown"
      }

      return nil

    @unknown default:
      return "settings.notif.permission.unknown"
    }
  }

  private var hasSystemSoundNotifications: Bool {
    notificationConfigsForPermission.contains { config in
      return
        (config.alertEnabled && config.alertSound == .system)
        || (config.preReminderEnabled && config.preReminderSound == .system)
        || (config.postReminderEnabled && config.postReminderSound == .system)
    }
  }

  private var hasEnabledNotifications: Bool {
    notificationConfigsForPermission.contains { config in
      config.alertEnabled || config.preReminderEnabled || config.postReminderEnabled
    }
  }

  private var notificationConfigsForPermission: [PrayerNotificationConfig] {
    var configs = PrayerKind.allCases.map { prefs.config(for: $0) }
    if prefs.jumuahOverrideEnabled {
      configs.append(prefs.jumuahConfig)
    }
    return configs
  }

  private func isPreviewing(slot: PrayerNotificationSoundSlot) -> Bool {
    guard case .playing(let context) = previewController.state else { return false }
    return context.source == .preview && context.prayer == selectedPrayer && context.slot == slot
  }

  private func stopPreviewIfNeeded(slot: PrayerNotificationSoundSlot) {
    if isPreviewing(slot: slot) {
      previewController.stop()
    }
  }

  private func togglePreview(sound: AdhanSound, slot: PrayerNotificationSoundSlot) {
    if isPreviewing(slot: slot) {
      previewController.stop()
      return
    }

    if sound == .system {
      NSSound.beep()
      return
    }

    guard
      let resource = sound.audioPlaybackResource(refreshCustomFile: {
        setSound(.custom($0), for: slot)
      })
    else { return }

    previewController.play(
      AudioPlaybackRequest(
        resource: resource,
        volume: Float(prefs.alertVolume) / 100.0,
        context: AudioPlaybackContext(prayer: selectedPrayer, source: .preview, slot: slot)
      )
    )
  }

  private func setSound(_ sound: AdhanSound, for slot: PrayerNotificationSoundSlot) {
    var updatedConfig = config.wrappedValue
    updatedConfig.setSound(sound, for: slot)
    config.wrappedValue = updatedConfig
  }

  @MainActor
  private func requestAuthorizationIfNeeded() async {
    #if DEBUG
      // The tests that drive this tab in the real app must never bring up a consent
      // prompt: show the status, never ask.
      if prefs.defaults.bool(forKey: DebugOptions.withoutSystemPromptsKey) {
        await refreshAuthorizationStatus(rescheduleOnGrant: false)
        return
      }
    #endif
    guard !permissionRequestInFlight, hasEnabledNotifications else {
      await refreshAuthorizationStatus(rescheduleOnGrant: false)
      return
    }

    // Claimed before the first wait, so overlapping calls ask macOS once.
    permissionRequestInFlight = true
    defer { permissionRequestInFlight = false }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let wasDelivering = notificationsCanDeliver(authorizationStatus)
    applyNotificationSettings(settings)

    guard settings.authorizationStatus == .notDetermined else { return }

    permissionRequestFailed = false

    do {
      _ = try await center.requestAuthorization(options: [.alert, .sound])
    } catch {
      permissionRequestFailed = true
    }

    let updatedSettings = await center.notificationSettings()
    applyNotificationSettings(updatedSettings)

    if !wasDelivering && notificationsCanDeliver(updatedSettings.authorizationStatus) {
      notifyChange()
    }
  }

  @MainActor
  private func refreshAuthorizationStatus(rescheduleOnGrant: Bool) async {
    let wasDelivering = notificationsCanDeliver(authorizationStatus)
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    applyNotificationSettings(settings)

    if rescheduleOnGrant && !wasDelivering && notificationsCanDeliver(settings.authorizationStatus)
    {
      notifyChange()
    }
  }

  // A prior `requestAuthorization` throw stays in `permissionRequestFailed`
  // forever otherwise, since the request-flow guards return early once the
  // status leaves `.notDetermined`. Observing any resolved state means the
  // system has an authoritative answer, so let the normal status message win.
  private func applyNotificationSettings(_ settings: UNNotificationSettings) {
    notificationSettings = settings
    if settings.authorizationStatus != .notDetermined {
      permissionRequestFailed = false
    }
  }

  private func notificationsCanDeliver(_ status: UNAuthorizationStatus?) -> Bool {
    switch status {
    case .authorized, .provisional:
      return true
    case .denied, .notDetermined, nil:
      return false
    @unknown default:
      return false
    }
  }

  private func openNotificationSettings() {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.salah-kit.Salah"
    let urlStrings = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)",
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.notifications",
    ]

    for urlString in urlStrings {
      guard let url = URL(string: urlString) else { continue }
      if NSWorkspace.shared.open(url) {
        return
      }
    }
  }
}
