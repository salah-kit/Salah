import Foundation

/// The bundle that holds the app's resources: the String Catalog and the bundled
/// sounds. It is `Bundle.main` in the app.
///
/// Test seam: the GuidanceTests bundle compiles the app's sources without a host
/// app, so its main bundle is the test runner. It points `bundle` at itself, where
/// the same catalog and sounds are copied.
enum AppResources {
  static var bundle: Bundle = .main

  /// Where `localizedString` resolves keys. Stays `.main` while `bundle` is the
  /// main bundle, so the app's lookups are exactly what they were.
  static var localizationBundle: LocalizedStringResource.BundleDescription {
    bundle == .main ? .main : .atURL(bundle.bundleURL)
  }
}
