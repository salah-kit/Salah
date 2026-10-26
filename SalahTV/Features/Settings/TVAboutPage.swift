import SwiftUI

/// The version, where the times and recordings come from, and what stays on this Apple TV.
/// The adhan recordings' licence asks for this credit wherever they play.
struct TVAboutPage: View {
  @Environment(IOSAppStore.self) private var store

  var body: some View {
    let copy = TVSettingsCopy(locale: store.locale)
    ScrollView {
      VStack(alignment: .leading, spacing: 40) {
        section(
          copy.text("Salah for Apple TV", "صلاة لجهاز Apple TV"),
          copy.copy.format("Version %@", "الإصدار %@", version))
        section(
          copy.text("Prayer times", "أوقات الصلاة"),
          copy.text(
            "Calculated on this Apple TV with SalahKit and SalahTimes, open-source Swift packages. Salah has no account, analytics or tracking.",
            "تُحسب على جهاز Apple TV هذا بحزمتي SalahKit وSalahTimes مفتوحتي المصدر بلغة Swift. لا حساب في صلاة ولا تحليلات ولا تتبّع."
          ))
        section(
          copy.text("Privacy", "الخصوصية"),
          copy.text(
            "Your location and settings stay on this Apple TV. Finding your city sends this Apple TV’s location, or the city you search for, to Apple Maps.",
            "يبقى موقعك وإعداداتك على جهاز Apple TV هذا. لمعرفة مدينتك يُرسَل موقع الجهاز أو اسم المدينة التي تبحث عنها إلى خرائط Apple."
          ))
        let credits = noticeParagraphs
        VStack(alignment: .leading, spacing: 20) {
          section(copy.text("Audio credits", "حقوق الصوت"), credits.first ?? "")
          ForEach(Array(credits.dropFirst().enumerated()), id: \.offset) { _, text in
            paragraph(text)
          }
        }
        section(
          copy.text("Source code", "الشيفرة المصدرية"), "github.com/salah-kit/Salah"
        )
        .accessibilityIdentifier("about.source")
      }
      .frame(maxWidth: 1400, alignment: .leading)
      .padding(.horizontal, TVMetrics.safeHorizontal)
      .padding(.vertical, TVMetrics.safeVertical)
    }
    .navigationTitle(copy.text("About Salah", "عن صلاة"))
  }

  /// Text alone can't take focus, and tvOS scrolls by moving focus, so every section and
  /// paragraph takes focus on its own and moving down reaches the end.
  private func section(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(verbatim: title)
        .font(.headline.bold())
        .foregroundStyle(TVTheme.labelPrimary)
      prose(text)
    }
    .accessibilityElement(children: .combine)
    .focusable()
  }

  private func paragraph(_ text: String) -> some View {
    prose(text).focusable()
  }

  private func prose(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.callout)
      .foregroundStyle(TVTheme.labelSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var version: String {
    let info = AppResources.bundle.infoDictionary
    let marketing = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return "\(marketing) (\(build))"
  }

  /// The bundled licence notice, as shipped beside the recordings.
  private var notice: String {
    guard let url = AppResources.bundle.url(forResource: "NOTICE", withExtension: nil),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return "Adhan recordings by Ahmed Khalaf, CC BY 4.0." }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The notice split on its blank lines, so no paragraph is taller than the screen.
  private var noticeParagraphs: [String] {
    var paragraphs: [String] = []
    var lines: [String] = []
    for line in notice.components(separatedBy: .newlines) {
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        if !lines.isEmpty { paragraphs.append(lines.joined(separator: "\n")) }
        lines = []
      } else {
        lines.append(line)
      }
    }
    if !lines.isEmpty { paragraphs.append(lines.joined(separator: "\n")) }
    return paragraphs
  }
}
