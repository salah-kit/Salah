import Foundation
import SalahWidgets
import TVServices
import UIKit

/// Salah's Top Shelf: inset banners of the next prayer, today's prayers and the room display,
/// drawn from the settings the app mirrors into the App Group. With no location yet it
/// provides nothing, and the system shows the static Top Shelf image.
final class SalahTopShelfProvider: TVTopShelfContentProvider {
  override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
    let isDark = await MainActor.run { UITraitCollection.current.userInterfaceStyle != .light }
    guard
      let snapshot = TopShelfSnapshot(
        settings: SharedValue<SalahSettings>.settings.load(), date: Date(), isDark: isDark)
    else { return nil }
    let images = await MainActor.run { TopShelfImageFiles.write(snapshot: snapshot) }
    var items: [TVTopShelfItem] = []
    for banner in snapshot.banners {
      guard let urls = images[banner] else { continue }
      let item = TVTopShelfItem(identifier: banner.rawValue)
      item.title = snapshot.accessibilityTitle(of: banner)
      item.setImageURL(urls.scale1, for: .screenScale1x)
      item.setImageURL(urls.scale2, for: .screenScale2x)
      item.displayAction = TVTopShelfAction(url: banner.url)
      item.playAction = TVTopShelfAction(url: banner.url)
      items.append(item)
    }
    return items.isEmpty ? nil : TVTopShelfInsetContent(items: items)
  }
}

/// Writes each banner's images where the system can read them.
@MainActor
enum TopShelfImageFiles {
  struct URLs: Sendable {
    var scale1: URL
    var scale2: URL
  }

  /// The images of each banner at both screen scales. A banner whose images couldn't be
  /// written is left out.
  static func write(snapshot: TopShelfSnapshot) -> [TopShelfBanner: URLs] {
    guard let folder = folder() else { return [:] }
    var keep: Set<String> = []
    var written: [TopShelfBanner: URLs] = [:]
    for banner in snapshot.banners {
      let fingerprint = snapshot.fingerprint(of: banner)
      var urls: [URL] = []
      for scale in [1.0, 2.0] {
        let name = "\(banner.rawValue)-\(fingerprint)@\(Int(scale))x.png"
        let url = folder.appendingPathComponent(name)
        keep.insert(name)
        if FileManager.default.fileExists(atPath: url.path) {
          urls.append(url)
        } else if let data = TopShelfImages.png(of: banner, snapshot: snapshot, scale: scale),
          (try? data.write(to: url, options: .atomic)) != nil
        {
          urls.append(url)
        }
      }
      if urls.count == 2 { written[banner] = URLs(scale1: urls[0], scale2: urls[1]) }
    }
    // Images of other times, languages and appearances are no longer shown.
    let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    for name in existing where !keep.contains(name) {
      try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
    return written
  }

  /// The App Group's caches: the system reads the images from there, and may clear them.
  private static func folder() -> URL? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SalahWidgetConstants.appGroupID)
    else { return nil }
    let folder = container.appendingPathComponent("Library/Caches/TopShelf", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}
