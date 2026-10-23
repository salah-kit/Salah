import Foundation
import MapKit
import Observation
import SalahCore

nonisolated struct IOSCityResult: Identifiable, Hashable, Sendable {
  var title: String
  var subtitle: String
  var location: PrayerLocation
  var id: String { "\(location.latitude)/\(location.longitude)/\(location.timeZone.identifier)" }
}

/// Search results are complete locations, so selecting a result cannot race a later resolution.
@MainActor @Observable
final class IOSCitySearchService {
  private(set) var query = ""
  private(set) var results: [IOSCityResult] = []
  private(set) var isSearching = false
  private(set) var errorMessage: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private let searcher: any IOSCitySearching
  @ObservationIgnored private let debounce: Duration
  @ObservationIgnored private var generation = UUID()

  init(
    searcher: any IOSCitySearching = IOSMapKitCitySearcher(),
    debounce: Duration = .milliseconds(300)
  ) {
    self.searcher = searcher
    self.debounce = debounce
  }

  func update(query: String) {
    cancel()
    self.query = query
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 2 else { return }
    let token = generation
    isSearching = true
    task = Task { [weak self] in
      do {
        try await Task.sleep(for: self?.debounce ?? .milliseconds(300))
        guard let self, self.generation == token else { return }
        let resolved = try await self.searcher.search(text)
        try Task.checkCancellation()
        guard self.generation == token else { return }
        var identifiers = Set<String>()
        self.results = resolved.filter { identifiers.insert($0.id).inserted }
        self.isSearching = false
        if self.results.isEmpty {
          self.errorMessage = "No cities found. Try a city and country name."
        }
      } catch is CancellationError {
      } catch {
        guard let self, self.generation == token else { return }
        self.isSearching = false
        self.errorMessage = "Could not search cities. Check your connection and try again."
      }
    }
  }

  func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
    searcher.cancel()
    query = ""
    results = []
    errorMessage = nil
    isSearching = false
  }
}

@MainActor protocol IOSCitySearching {
  func search(_ query: String) async throws -> [IOSCityResult]
  func cancel()
}

/// MapKit is the location-data boundary; city selection receives only resolved zones.
@MainActor final class IOSMapKitCitySearcher: IOSCitySearching {
  private var localSearch: MKLocalSearch?
  private var geocoding: MKReverseGeocodingRequest?

  func search(_ query: String) async throws -> [IOSCityResult] {
    let request = MKLocalSearch.Request(naturalLanguageQuery: query)
    request.resultTypes = .address
    let search = MKLocalSearch(request: request)
    localSearch = search
    let response = try await search.start()
    try Task.checkCancellation()
    var resolved: [IOSCityResult] = []
    for item in response.mapItems.prefix(10) {
      try Task.checkCancellation()
      var location = IOSMapLocation.resolve(item)
      if location == nil, let geocoding = MKReverseGeocodingRequest(location: item.location) {
        self.geocoding = geocoding
        let items = try await geocoding.mapItems
        try Task.checkCancellation()
        if let geocoded = items.first {
          location = IOSMapLocation.resolve(geocoded, coordinate: item.location.coordinate)
        }
      }
      guard let location else { continue }
      let city = location.name ?? item.name ?? query
      let country =
        item.addressRepresentations?.regionName
        ?? location.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) }
      let title = [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
      let context = item.addressRepresentations?.cityWithContext(.short) ?? ""
      let region: String
      if context.hasPrefix(city + ", ") {
        region = String(context.dropFirst(city.count + 2))
      } else if context == city {
        region = ""
      } else {
        region = context
      }
      resolved.append(IOSCityResult(title: title, subtitle: region, location: location))
    }
    return resolved
  }

  func cancel() {
    localSearch?.cancel()
    localSearch = nil
    geocoding?.cancel()
    geocoding = nil
  }
}
