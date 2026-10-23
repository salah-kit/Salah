import SalahAlerts
import SalahCore
import SwiftUI
import UIKit

struct IOSPrayerAlertsSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(IOSNotificationService.self) private var notifications
  @Environment(\.scenePhase) private var scenePhase
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      if notifications.status != .authorized { IOSNotificationPermissionSection() }
      Section(copy.text("Prayers", "الصلوات")) {
        ForEach(PrayerKind.allCases, id: \.self) { kind in
          NavigationLink {
            IOSPrayerAlertSettingsView(target: .prayer(kind))
          } label: {
            let alerts = store.preferences.alerts(for: kind)
            IOSSettingsRow(
              title: copy.prayer(kind), value: enabled(alerts),
              subtitle: kind == .sunrise
                ? copy.text("Optional event alert", "تنبيه اختياري للشروق") : summary(alerts),
              prayer: kind)
          }
          .accessibilityIdentifier("alerts.\(kind.rawValue)")
          .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
        }
      }
      Section {
        NavigationLink {
          IOSPrayerAlertSettingsView(target: .jumuah)
        } label: {
          IOSSettingsRow(
            title: copy.text("Jumu’ah", "الجمعة"),
            value: store.preferences.jumuahOverrideEnabled
              ? enabled(store.preferences.jumuahAlerts) : copy.text("Dhuhr", "الظهر"),
            subtitle: store.preferences.jumuahOverrideEnabled
              ? copy.text("Friday override", "إعدادات خاصة بالجمعة") + " · "
                + summary(store.preferences.jumuahAlerts)
              : copy.text("Uses Dhuhr’s alerts", "تستخدم تنبيهات الظهر"),
            prayer: .dhuhr, jumuah: true)
        }
        .accessibilityIdentifier("alerts.jumuah")
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
      } header: {
        Text(copy.text("Friday", "الجمعة"))
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            copy.text(
              "Alerts are scheduled on this iPhone. If notifications are off, Salah still shows the times.",
              "تُجدول التنبيهات على iPhone. إذا كانت الإشعارات معطلة، يظل تطبيق صلاة يعرض المواقيت.")
          )
          if notifications.status == .authorized, !notifications.isRefreshing,
            let report = notifications.report
          {
            Text(
              copy.format(
                "%@ upcoming alerts scheduled", "تمت جدولة %@ من التنبيهات القادمة",
                copy.number(report.confirmed.count))
            )
            .accessibilityIdentifier("alerts.scheduledCount")
            .accessibilityValue(String(report.confirmed.count))
            if let coverage = report.confirmedCoveredUntil {
              Text(
                copy.format(
                  "Scheduled through %@. Open Salah regularly to keep alerts up to date.",
                  "مجدولة حتى %@. افتح تطبيق صلاة بانتظام لتحديث التنبيهات.",
                  coverage.formatted(
                    Date.FormatStyle(
                      date: .abbreviated, time: .omitted, locale: store.locale,
                      timeZone: store.timeZone)))
              )
              .accessibilityIdentifier("alerts.coverage")
            }
          }
        }
      }
      if let message = notifications.errorMessage {
        Section {
          Text(IOSL10n.text(message, locale: store.locale))
            .foregroundStyle(IOSTheme.labelSecondary)
          Button(copy.text("Try again", "حاول مجددًا")) {
            Task {
              await notifications.refresh(schedule: store.schedule, preferences: store.preferences)
            }
          }
          .accessibilityIdentifier("alerts.retryScheduling")
        }
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Prayer alerts", "تنبيهات الصلاة"))
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("alerts.form")
    .task { await notifications.refreshAuthorization() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await notifications.refreshAuthorization() } }
    }
  }

  private func enabled(_ alerts: IOSPrayerAlertSettings) -> String {
    alerts.atTime || alerts.beforeEnabled || alerts.afterEnabled
      ? copy.text("On", "مفعّل") : copy.text("Off", "معطّل")
  }

  private func summary(_ alerts: IOSPrayerAlertSettings) -> String {
    var parts: [String] = []
    if alerts.atTime { parts.append(copy.sound(alerts.sound)) }
    if alerts.beforeEnabled {
      parts.append(copy.format("%@ before", "%@ قبل", copy.minutes(alerts.beforeMinutes)))
    }
    if alerts.afterEnabled {
      parts.append(copy.format("%@ after", "%@ بعد", copy.minutes(alerts.afterMinutes)))
    }
    return parts.isEmpty ? copy.text("No alerts", "بلا تنبيهات") : parts.joined(separator: " · ")
  }
}

private struct IOSNotificationPermissionSection: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(IOSNotificationService.self) private var notifications
  @Environment(\.openURL) private var openURL
  @State private var requesting = false
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Section {
      Button {
        if notifications.status == .notDetermined {
          requesting = true
          Task {
            await notifications.requestAuthorization()
            requesting = false
          }
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
          openURL(url)
        }
      } label: {
        HStack(spacing: 12) {
          IOSSettingsRow(
            title: notifications.status == .notDetermined
              ? copy.text("Allow notifications", "السماح بالإشعارات")
              : copy.text("Open Settings", "فتح الإعدادات"),
            symbol: "bell.badge")
          if requesting { ProgressView() }
        }
      }
      .disabled(requesting)
      .accessibilityIdentifier("alerts.permission")
    } footer: {
      Text(
        copy.text(
          "Your alert choices are saved. Allow notifications in iPhone Settings to receive them. Focus and Scheduled Summary can affect when banners appear.",
          "تُحفظ اختيارات التنبيهات. اسمح بالإشعارات في إعدادات iPhone لاستلامها. قد يؤثر التركيز والملخص المجدول في وقت ظهور اللافتات."
        ))
    }
  }
}

enum IOSPrayerAlertTarget: Hashable {
  case prayer(PrayerKind)
  case jumuah

  var identifier: String {
    switch self {
    case .prayer(let kind): kind.rawValue
    case .jumuah: "jumuah"
    }
  }
}

struct IOSPrayerAlertSettingsView: View {
  let target: IOSPrayerAlertTarget
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      if target == .jumuah {
        Section {
          Toggle(
            copy.text("Different alerts on Friday", "تنبيهات مختلفة يوم الجمعة"),
            isOn: fridayOverride
          )
          .accessibilityIdentifier("alert.fridayOverride")
        } header: {
          Text(copy.text("Friday", "الجمعة"))
        } footer: {
          Text(
            copy.text(
              "When off, Fridays use Dhuhr’s alerts.", "عند التعطيل، تستخدم الجمعة تنبيهات الظهر."))
        }
      }

      Section {
        Toggle(
          isSunrise
            ? copy.text("Alert at sunrise", "تنبيه عند الشروق")
            : copy.text("Alert at prayer time", "تنبيه عند وقت الصلاة"),
          isOn: binding(\.atTime)
        )
        .accessibilityIdentifier("alert.\(target.identifier).at.enabled")
        if alerts.atTime { soundRow(\.sound, slot: "at", detail: atTimeTitle) }
      } header: {
        Text(atTimeTitle)
      } footer: {
        if isSunrise {
          Text(
            copy.text(
              "Sunrise marks the day; it is not a prayer. Choose a sound if you want an alert.",
              "الشروق بداية النهار وليس صلاة. اختر صوتًا إذا أردت تنبيهًا."))
        }
      }
      .disabled(inheritingDhuhr)

      Section {
        Toggle(copy.text("Remind me before", "تذكيري قبل الموعد"), isOn: binding(\.beforeEnabled))
          .accessibilityIdentifier("alert.\(target.identifier).before.enabled")
        if alerts.beforeEnabled {
          Stepper(value: binding(\.beforeMinutes), in: 1...120) {
            IOSSettingsRow(
              title: copy.text("Minutes before", "الدقائق قبل الموعد"),
              subtitle: copy.minutes(alerts.beforeMinutes))
          }
          .accessibilityIdentifier("alert.\(target.identifier).before.minutes")
          .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
          .accessibilityValue(copy.number(alerts.beforeMinutes))
          soundRow(\.beforeSound, slot: "before", detail: copy.text("Before", "قبل الموعد"))
        }
      } header: {
        Text(copy.text("Before", "قبل الموعد"))
      }
      .disabled(inheritingDhuhr)

      Section {
        Toggle(copy.text("Remind me after", "تذكيري بعد الموعد"), isOn: binding(\.afterEnabled))
          .accessibilityIdentifier("alert.\(target.identifier).after.enabled")
        if alerts.afterEnabled {
          Stepper(value: binding(\.afterMinutes), in: 1...120) {
            IOSSettingsRow(
              title: copy.text("Minutes after", "الدقائق بعد الموعد"),
              subtitle: copy.minutes(alerts.afterMinutes))
          }
          .accessibilityIdentifier("alert.\(target.identifier).after.minutes")
          .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
          .accessibilityValue(copy.number(alerts.afterMinutes))
          soundRow(\.afterSound, slot: "after", detail: copy.text("After", "بعد الموعد"))
        }
      } header: {
        Text(copy.text("After", "بعد الموعد"))
      } footer: {
        Text(
          copy.text(
            "Choose 1–120 minutes. Each reminder keeps its own timing and sound.",
            "اختر من ١ إلى ١٢٠ دقيقة. لكل تذكير توقيته وصوته المستقلان."))
      }
      .disabled(inheritingDhuhr)
      if store.preferences.muteSounds {
        Section {
          Text(
            copy.text(
              "Sounds are muted. Notifications and reminders still arrive. Turn off Mute sounds to change or preview audio.",
              "الأصوات مكتومة. تستمر الإشعارات والتذكيرات. عطّل كتم الأصوات لتغيير الصوت أو معاينته."
            )
          )
          .font(.footnote)
          .foregroundStyle(IOSTheme.labelSecondary)
          .listRowBackground(Color.clear)
        }
      }
    }
    .iosSettingsForm()
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("alert.\(target.identifier).form")
  }

  private var title: String {
    switch target {
    case .prayer(let kind): copy.prayer(kind)
    case .jumuah: copy.text("Jumu’ah", "الجمعة")
    }
  }

  private var isSunrise: Bool { target == .prayer(.sunrise) }
  private var inheritingDhuhr: Bool {
    target == .jumuah && !store.preferences.jumuahOverrideEnabled
  }
  private var atTimeTitle: String {
    isSunrise
      ? copy.text("At sunrise", "عند الشروق") : copy.text("At prayer time", "عند وقت الصلاة")
  }
  private var alerts: IOSPrayerAlertSettings {
    switch target {
    case .prayer(let kind): store.preferences.alerts(for: kind)
    case .jumuah:
      store.preferences.jumuahOverrideEnabled
        ? store.preferences.jumuahAlerts : store.preferences.alerts(for: .dhuhr)
    }
  }

  private var fridayOverride: Binding<Bool> {
    Binding(
      get: { store.preferences.jumuahOverrideEnabled },
      set: { store.setJumuahOverrideEnabled($0) })
  }

  private func binding<Value>(_ path: WritableKeyPath<IOSPrayerAlertSettings, Value>) -> Binding<
    Value
  > {
    Binding(
      get: { alerts[keyPath: path] },
      set: { value in
        guard !inheritingDhuhr else { return }
        store.updatePreferences { preferences in
          switch target {
          case .prayer(let kind):
            var alert = preferences.alerts(for: kind)
            alert[keyPath: path] = value
            preferences.notifications[kind] = alert
          case .jumuah:
            preferences.jumuahAlerts[keyPath: path] = value
          }
        }
      })
  }

  private func soundRow(
    _ path: WritableKeyPath<IOSPrayerAlertSettings, IOSSound>, slot: String, detail: String
  ) -> some View {
    NavigationLink {
      IOSNotificationSoundSettingsView(
        sound: binding(path), context: "\(title) · \(detail)")
    } label: {
      IOSSettingsRow(title: copy.text("Sound", "الصوت"), value: copy.sound(alerts[keyPath: path]))
    }
    .disabled(store.preferences.muteSounds)
    .accessibilityIdentifier("alert.\(target.identifier).\(slot).sound")
  }
}
