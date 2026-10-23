import Foundation

/// The bundle that holds the resources: the String Catalog, the bundled sounds and the
/// prayer glyphs. It is `Bundle.main` in the app and in the widget extension.
///
/// Test seam: the SalahTests bundle compiles the app's sources without a host
/// app, so its main bundle is the test runner. It points `bundle` at itself, where
/// the same catalog and sounds are copied.
nonisolated enum AppResources {
  // Set once, before anything reads it: by the tests' principal class.
  nonisolated(unsafe) static var bundle: Bundle = .main

  /// Where `localizedString` resolves keys. Stays `.main` while `bundle` is the
  /// main bundle, so the app's lookups are exactly what they were.
  static var localizationBundle: LocalizedStringResource.BundleDescription {
    bundle == .main ? .main : .atURL(bundle.bundleURL)
  }
}
