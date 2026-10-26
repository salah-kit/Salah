import SalahCore
import SwiftUI

/// Choosing a city: the system keyboard at the top, matches below as people type. The
/// remote's microphone dictates. A city needs no location permission.
struct TVCitySearchView: View {
  /// During setup, choosing a city completes it; from Settings, it returns to Location.
  let completesOnboarding: Bool

  @Environment(IOSAppStore.self) private var store
  @Environment(TVAppRuntime.self) private var runtime
  @Environment(IOSCitySearchService.self) private var search
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    let copy = TVCopy(locale: store.locale)
    List {
      Section {
        ForEach(search.results) { result in
          Button {
            runtime.choose(city: result.location)
            if !completesOnboarding { dismiss() }
          } label: {
            HStack {
              Text(verbatim: result.title)
              Spacer(minLength: 24)
              Text(verbatim: result.subtitle).foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("location.result.\(result.id)")
        }
      } footer: {
        Group {
          if search.isSearching {
            ProgressView()
          } else if let error = search.errorMessage {
            Text(verbatim: message(copy, english: error))
          } else {
            Text(
              verbatim: copy(
                "Times for the city are calculated on this Apple TV. The search uses Apple Maps.",
                "تُحسب أوقات المدينة على جهاز Apple TV هذا. ويستخدم البحث خرائط Apple."))
          }
        }
        .accessibilityIdentifier("location.status")
      }
    }
    .searchable(text: $query, prompt: copy("City", "المدينة"))
    .onChange(of: query) { _, text in search.update(query: text) }
    .onDisappear { search.cancel() }
    .accessibilityIdentifier("location.search")
  }

  /// The search's own messages, in the selected language.
  private func message(_ copy: TVCopy, english: String) -> String {
    switch english {
    case "No cities found. Try a city and country name.":
      copy(english, "لم يُعثر على مدن. جرّب اسم مدينة وبلد.")
    case "Could not search cities. Check your connection and try again.":
      copy(english, "تعذّر البحث عن المدن. تحقّق من الاتصال وحاول مرة أخرى.")
    default:
      english
    }
  }
}
