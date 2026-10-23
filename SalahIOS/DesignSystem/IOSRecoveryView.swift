import SwiftUI

/// A permission or unavailable-data state always includes its next useful action.
struct IOSRecoveryView: View {
  let title: String
  let message: String
  var symbol: String = "location.slash"
  let primaryTitle: String
  var secondaryTitle: String? = nil
  var primaryAction: () -> Void
  var secondaryAction: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        Image("OnboardingGeometry")
          .resizable()
          .scaledToFit()
        Image(systemName: symbol)
          .font(.system(size: 52, weight: .regular))
          .foregroundStyle(IOSTheme.warning)
      }
      .frame(width: 180, height: 180)
      .accessibilityHidden(true)
      Text(verbatim: title)
        .font(.title2.bold())
        .foregroundStyle(IOSTheme.labelPrimary)
      Text(verbatim: message)
        .font(.body)
        .foregroundStyle(IOSTheme.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: primaryAction) {
        Text(verbatim: primaryTitle)
          .frame(maxWidth: .infinity)
          .foregroundStyle(IOSTheme.labelOnAccent)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .tint(IOSTheme.accentFill)
      if let secondaryTitle, let secondaryAction {
        Button(action: secondaryAction) {
          Text(verbatim: secondaryTitle).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(IOSTheme.accentText)
      }
    }
    .multilineTextAlignment(.center)
    .padding(24)
    .frame(maxWidth: 520)
  }
}
