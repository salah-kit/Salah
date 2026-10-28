import SwiftUI

/// Before the iPhone sends any preferences: where to set Salah up. The watch asks a reachable
/// iPhone for them, and shows the times as soon as they arrive.
struct WatchSetupView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(\.colorSchemeContrast) private var contrast
  private var theme: WatchTheme { WatchTheme(contrast: contrast) }

  var body: some View {
    let copy = WatchCopy(locale: store.locale)
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: "iphone")
          .font(.title2)
          .foregroundStyle(theme.accentText)
          .accessibilityHidden(true)
        Text(verbatim: copy("Set up Salah on your iPhone", "أعدّ صلاة على جهاز iPhone"))
          .font(.headline)
          .foregroundStyle(theme.labelPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Text(
          verbatim: copy(
            "Choose a place in Salah on your iPhone. Its prayer times appear here.",
            "اختر مكانًا في تطبيق صلاة على جهاز iPhone لتظهر أوقات الصلاة هنا.")
        )
        .font(.footnote)
        .foregroundStyle(theme.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, WatchMetrics.screenInset)
    }
    .background { WatchSkyBackground(phase: .neutral) }
    .navigationTitle(Text(verbatim: copy("Salah", "صلاة")))
    .navigationBarTitleDisplayMode(.inline)
    // The page's identifier stays its own; its parts keep theirs.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("screen.setup")
  }
}
