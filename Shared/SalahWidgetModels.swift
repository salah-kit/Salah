import Foundation

/// Mirrors `MenuBarStatusTone` from the app so the widget speaks the same state
/// language the menu bar already uses.
nonisolated enum SalahWidgetTone: String, Codable, Equatable, Sendable {
  case normal
  case imminent
  case playingPreReminderAudio
  case playingPrayerAudio
  case playingPostReminderAudio
  case silent
}

/// Resolved per-row display state for the medium/large schedules.
nonisolated enum SalahWidgetRowState: Equatable {
  case passed
  case current
  case next(SalahWidgetTone)
  case upcoming
  case active(SalahWidgetTone)
}

/// Localized chrome strings for the widget faces and the menu-bar dropdown, which draw
/// them in the user's language whatever the process's language is. The widget
/// extension has no access to the app's String Catalog, so they live here.
///
/// `notAvailable` and `nextUnknown` came with the move onto SalahKit, after the other
/// labels, and need a native speaker's review in every language but English. So do the
/// `sinceSpoken` and `sinceLine` phrases of Urdu, Indonesian, Turkish, Persian, Bengali and
/// Malay, which were drafted to fix their word order.
nonisolated struct SalahWidgetLabels: Equatable, Sendable {
  var nextPrayer: String
  var tomorrow: String
  var now: String
  /// What VoiceOver reads while a prayer counts up: `%1$@` is the prayer's name and `%2$@`
  /// the time since it began, spelled out ("Dhuhr · started 5 minutes ago"). Each language
  /// puts them in its own order.
  var sinceSpoken: String
  /// The small widget's line after a prayer: `%1$@` is the prayer's name and `%2$@` the time
  /// since it began ("Dhuhr since: +1:30").
  var sinceLine: String
  var remaining: String
  var silent: String
  var stopShort: String
  /// Generic stop label for the larger sizes - covers adhan, du'ā', and reminders.
  var stopAudio: String
  /// Hint shown on the whole-widget stop control while audio plays.
  var tapToStop: String
  /// Shown when the widget's timeline ran out before WidgetKit asked for a new one.
  var openToUpdate: String
  // Playing-banner titles (rendered by the widget, composed by the app):
  var playingAdhan: String
  var playingDua: String
  var playingPreReminder: String
  var playingPostReminder: String
  // Reminder summaries:
  var alertOn: String
  var alertOff: String
  var before: String
  var after: String
  /// The era after a Hijri year ("1447 H").
  var hijriSuffix: String
  /// Shown when the schedule has no times to show for the place.
  var timesUnavailable: String
  /// The time of a prayer the calculation can't give today, for VoiceOver.
  var notAvailable: String
  /// Shown in the focus's place when the next prayer's time isn't known.
  var nextUnknown: String

  static let english = SalahWidgetLabels(
    nextPrayer: "Next Prayer",
    tomorrow: "Tomorrow",
    now: "Now",
    sinceSpoken: "%1$@ · started %2$@ ago",
    sinceLine: "%1$@ since: %2$@",
    remaining: "remaining",
    silent: "Silent",
    stopShort: "Stop",
    stopAudio: "Stop Audio",
    tapToStop: "Tap to stop",
    openToUpdate: "Open Salah to update",
    playingAdhan: "Playing Adhan",
    playingDua: "Playing Du’ā’",
    playingPreReminder: "Pre-reminder",
    playingPostReminder: "Post-reminder",
    alertOn: "Alert on",
    alertOff: "Alert off",
    before: "before",
    after: "after",
    hijriSuffix: "H",
    timesUnavailable: "Prayer times aren't available for this location.",
    notAvailable: "Not available",
    nextUnknown: "Next prayer time not available"
  )

  static let arabic = SalahWidgetLabels(
    nextPrayer: "الصلاة القادمة",
    tomorrow: "غدًا",
    now: "الآن",
    sinceSpoken: "%1$@ · منذ %2$@",
    sinceLine: "%1$@ منذ: %2$@",
    remaining: "متبقّية",
    silent: "صامت",
    stopShort: "إيقاف",
    stopAudio: "إيقاف الصوت",
    tapToStop: "اضغط للإيقاف",
    openToUpdate: "افتح صلاة للتحديث",
    playingAdhan: "جارٍ تشغيل الأذان",
    playingDua: "جارٍ تشغيل الدعاء",
    playingPreReminder: "تذكير قبل الصلاة",
    playingPostReminder: "تذكير بعد الصلاة",
    alertOn: "تنبيه مُفعّل",
    alertOff: "تنبيه مُعطّل",
    before: "قبل",
    after: "بعد",
    hijriSuffix: "هـ",
    timesUnavailable: "أوقات الصلاة غير متوفرة لهذا الموقع.",
    notAvailable: "غير متاح",
    nextUnknown: "وقت الصلاة القادمة غير متاح"
  )

  static let french = SalahWidgetLabels(
    nextPrayer: "Prochaine prière",
    tomorrow: "Demain",
    now: "Maintenant",
    sinceSpoken: "%1$@ · depuis %2$@",
    sinceLine: "%1$@ depuis: %2$@",
    remaining: "restant",
    silent: "Silencieux",
    stopShort: "Arrêter",
    stopAudio: "Arrêter le son",
    tapToStop: "Appuyer pour arrêter",
    openToUpdate: "Ouvrir Salah pour actualiser",
    playingAdhan: "Adhan en cours",
    playingDua: "Du’ā’ en cours",
    playingPreReminder: "Rappel avant",
    playingPostReminder: "Rappel après",
    alertOn: "Alerte activée",
    alertOff: "Alerte désactivée",
    before: "avant",
    after: "après",
    hijriSuffix: "H",
    timesUnavailable: "Les horaires de prière ne sont pas disponibles pour ce lieu.",
    notAvailable: "Non disponible",
    nextUnknown: "Heure de la prochaine prière indisponible"
  )

  static let urdu = SalahWidgetLabels(
    nextPrayer: "اگلی نماز",
    tomorrow: "کل",
    now: "ابھی",
    sinceSpoken: "%1$@ · %2$@ سے",
    sinceLine: "%1$@ سے: %2$@",
    remaining: "باقی",
    silent: "خاموش",
    stopShort: "روکیں",
    stopAudio: "آواز روکیں",
    tapToStop: "روکنے کے لیے ٹیپ کریں",
    openToUpdate: "اپ ڈیٹ کے لیے Salah کھولیں",
    playingAdhan: "اذان چل رہی ہے",
    playingDua: "دعا چل رہی ہے",
    playingPreReminder: "نماز سے پہلے یاددہانی",
    playingPostReminder: "نماز کے بعد یاددہانی",
    alertOn: "الرٹ فعال",
    alertOff: "الرٹ غیر فعال",
    before: "پہلے",
    after: "بعد",
    hijriSuffix: "ھ",
    timesUnavailable: "اس مقام کے لیے اوقاتِ نماز دستیاب نہیں ہیں۔",
    notAvailable: "دستیاب نہیں",
    nextUnknown: "اگلی نماز کا وقت دستیاب نہیں"
  )

  static let indonesian = SalahWidgetLabels(
    nextPrayer: "Salat Berikutnya",
    tomorrow: "Besok",
    now: "Sekarang",
    sinceSpoken: "%1$@ · dimulai %2$@ yang lalu",
    sinceLine: "%1$@ sejak: %2$@",
    remaining: "tersisa",
    silent: "Senyap",
    stopShort: "Hentikan",
    stopAudio: "Hentikan Audio",
    tapToStop: "Ketuk untuk menghentikan",
    openToUpdate: "Buka Salah untuk memperbarui",
    playingAdhan: "Memutar Azan",
    playingDua: "Memutar Doa",
    playingPreReminder: "Pengingat sebelum",
    playingPostReminder: "Pengingat sesudah",
    alertOn: "Peringatan aktif",
    alertOff: "Peringatan nonaktif",
    before: "sebelum",
    after: "setelah",
    hijriSuffix: "H",
    timesUnavailable: "Waktu salat tidak tersedia untuk lokasi ini.",
    notAvailable: "Tidak tersedia",
    nextUnknown: "Waktu salat berikutnya tidak tersedia"
  )

  static let turkish = SalahWidgetLabels(
    nextPrayer: "Sonraki Namaz",
    tomorrow: "Yarın",
    now: "Şimdi",
    sinceSpoken: "%1$@ vaktinden beri %2$@ geçti",
    sinceLine: "%1$@ vaktinden beri: %2$@",
    remaining: "kaldı",
    silent: "Sessiz",
    stopShort: "Durdur",
    stopAudio: "Sesi Durdur",
    tapToStop: "Durdurmak için dokun",
    openToUpdate: "Güncellemek için Salah'ı aç",
    playingAdhan: "Ezan Çalıyor",
    playingDua: "Dua Çalıyor",
    playingPreReminder: "Namaz öncesi hatırlatma",
    playingPostReminder: "Namaz sonrası hatırlatma",
    alertOn: "Uyarı açık",
    alertOff: "Uyarı kapalı",
    before: "önce",
    after: "sonra",
    hijriSuffix: "H",
    timesUnavailable: "Bu konum için namaz vakitleri kullanılamıyor.",
    notAvailable: "Kullanılamıyor",
    nextUnknown: "Sonraki namaz vakti kullanılamıyor"
  )

  static let persian = SalahWidgetLabels(
    nextPrayer: "نماز بعدی",
    tomorrow: "فردا",
    now: "اکنون",
    sinceSpoken: "از وقت %1$@ %2$@ گذشته",
    sinceLine: "از وقت %1$@: %2$@",
    remaining: "مانده",
    silent: "بی‌صدا",
    stopShort: "توقف",
    stopAudio: "توقف صدا",
    tapToStop: "برای توقف ضربه بزنید",
    openToUpdate: "برای به‌روزرسانی Salah را باز کنید",
    playingAdhan: "در حال پخش اذان",
    playingDua: "در حال پخش دعا",
    playingPreReminder: "یادآور پیش از نماز",
    playingPostReminder: "یادآور پس از نماز",
    alertOn: "هشدار روشن",
    alertOff: "هشدار خاموش",
    before: "قبل",
    after: "بعد",
    hijriSuffix: "ه\u{200D}.ق",
    timesUnavailable: "اوقات شرعی برای این موقعیت در دسترس نیست.",
    notAvailable: "در دسترس نیست",
    nextUnknown: "زمان نماز بعدی در دسترس نیست"
  )

  static let bengali = SalahWidgetLabels(
    nextPrayer: "পরবর্তী নামাজ",
    tomorrow: "আগামীকাল",
    now: "এখন",
    sinceSpoken: "%1$@ শুরু হয়েছে %2$@ আগে",
    sinceLine: "%1$@ থেকে: %2$@",
    remaining: "বাকি",
    silent: "নীরব",
    stopShort: "বন্ধ",
    stopAudio: "অডিও বন্ধ করুন",
    tapToStop: "বন্ধ করতে ট্যাপ করুন",
    openToUpdate: "আপডেট করতে Salah খুলুন",
    playingAdhan: "আজান বাজছে",
    playingDua: "দোয়া বাজছে",
    playingPreReminder: "নামাজের আগে অনুস্মারক",
    playingPostReminder: "নামাজের পরে অনুস্মারক",
    alertOn: "সতর্কতা চালু",
    alertOff: "সতর্কতা বন্ধ",
    before: "আগে",
    after: "পরে",
    hijriSuffix: "হি.",
    timesUnavailable: "এই অবস্থানের জন্য নামাজের সময় পাওয়া যাচ্ছে না।",
    notAvailable: "পাওয়া যাচ্ছে না",
    nextUnknown: "পরবর্তী নামাজের সময় পাওয়া যাচ্ছে না"
  )

  static let malay = SalahWidgetLabels(
    nextPrayer: "Solat Seterusnya",
    tomorrow: "Esok",
    now: "Sekarang",
    sinceSpoken: "%1$@ · bermula %2$@ yang lalu",
    sinceLine: "%1$@ sejak: %2$@",
    remaining: "lagi",
    silent: "Senyap",
    stopShort: "Henti",
    stopAudio: "Hentikan Audio",
    tapToStop: "Ketik untuk hentikan",
    openToUpdate: "Buka Salah untuk kemas kini",
    playingAdhan: "Memainkan Azan",
    playingDua: "Memainkan Du’ā’",
    playingPreReminder: "Peringatan sebelum",
    playingPostReminder: "Peringatan selepas",
    alertOn: "Amaran hidup",
    alertOff: "Amaran mati",
    before: "sebelum",
    after: "selepas",
    hijriSuffix: "H",
    timesUnavailable: "Waktu solat tidak tersedia untuk lokasi ini.",
    notAvailable: "Tidak tersedia",
    nextUnknown: "Waktu solat seterusnya tidak tersedia"
  )

  /// Picks the table for the resolved language. Falls back to English for any
  /// language Salah doesn't translate (matching the app's catalog behavior).
  static func localized(forLanguageCode code: String?) -> SalahWidgetLabels {
    switch code {
    case "ar": return .arabic
    case "fr": return .french
    case "ur": return .urdu
    case "id": return .indonesian
    case "tr": return .turkish
    case "fa": return .persian
    case "bn": return .bengali
    case "ms": return .malay
    default: return .english
    }
  }
}

/// The minute unit of Salah's reminder phrases ("10m before", "قبل ١٠ د", "10 min avant").
/// Countdowns use SalahCore's `PrayerDurationFormat`; the reminder wording is Salah's own,
/// and these short display units may need a native review pass for the non-Latin
/// scripts.
nonisolated enum LocalizedTimeUnit {
  /// The minute unit as it trails a number. Every language except English separates it
  /// from the number with a space; English hugs it ("12m").
  static func minuteSuffix(forLanguageCode code: String?) -> String {
    let minute: String
    switch code {
    case "ar", "fa": minute = "د"
    case "fr", "ms": minute = "min"
    case "ur": minute = "منٹ"
    case "tr": minute = "dk"
    case "id": minute = "mnt"
    case "bn": minute = "মি"
    default: minute = "m"
    }
    if code == nil || code == "en" { return minute }
    return " \(minute)"
  }
}

extension SalahWidgetLabels {
  /// The VoiceOver count-up for a prayer: "Dhuhr · since 1 hour, 30 minutes".
  nonisolated func sinceSpoken(prayer: String, time: String) -> String {
    Self.fill(sinceSpoken, prayer: prayer, time: time)
  }

  /// The small widget's line after a prayer: "Dhuhr since: +1:30".
  nonisolated func sinceLine(prayer: String, time: String) -> String {
    Self.fill(sinceLine, prayer: prayer, time: time)
  }

  /// Puts the name and the time in a template's `%1$@` and `%2$@`, without the isolates and
  /// digits a locale's string formatting would add.
  nonisolated private static func fill(_ template: String, prayer: String, time: String) -> String {
    template.replacingOccurrences(of: "%1$@", with: prayer)
      .replacingOccurrences(of: "%2$@", with: time)
  }
}
