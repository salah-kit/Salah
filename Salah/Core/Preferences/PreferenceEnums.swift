import Foundation
import SalahTimes

nonisolated enum NextPrayerDisplayType: Int {
  case timeUntil = 0
  case timeOfPrayer = 1
  case none = 2
}

nonisolated enum NextPrayerDisplayName: Int {
  case full = 0
  case abbreviation = 1
  case none = 2
}

nonisolated enum MadhabPreference: Int {
  case shafi = 0
  case hanafi = 1

  /// SalahTimes' madhab.
  var madhab: Madhab {
    switch self {
    case .shafi: .shafi
    case .hanafi: .hanafi
    }
  }
}

/// The methods Salah's Calculation settings offer, stored by raw value.
nonisolated enum MethodPreference: Int, CaseIterable {
  case egyptian = 0
  case karachi = 1
  case northAmerica = 2
  case muslimWorldLeague = 3
  case ummAlQura = 4
  case gulf = 5
  case moonsightingCommittee = 6
  case custom = 7
  case kuwait = 8
  case qatar = 9
  case singapore = 10
  case tehran = 11

  /// SalahTimes' published method for this choice, or `nil` for the custom method, whose
  /// angles are the user's.
  var method: CalculationMethod? {
    switch self {
    case .egyptian: .egyptian
    case .karachi: .karachi
    case .northAmerica: .isna
    case .muslimWorldLeague: .muslimWorldLeague
    case .ummAlQura: .ummAlQura
    case .gulf: .dubai
    case .moonsightingCommittee: .moonsightingCommittee
    case .custom: nil
    case .kuwait: .kuwait
    case .qatar: .qatar
    case .singapore: .muis
    case .tehran: .tehran
    }
  }

  /// Salah's own choice of method for a country, when automatic detection is on.
  ///
  /// It differs from SalahTimes' sourced suggestions (`CalculationMethod.suggested`),
  /// which name methods this list doesn't offer (Diyanet, JAKIM, Kemenag) and leave out
  /// countries with no sourced method; adopting them would change these users' times,
  /// so it's a product decision of its own.
  static func detect(forCountry country: String) -> MethodPreference {
    switch country {
    case "EG", "SD", "SS", "LY", "DZ", "LB", "SY", "IL", "MA", "PS", "IQ", "TR", "MY":
      .egyptian
    case "PK", "IN", "BD", "AF", "JO":
      .karachi
    case "SA":
      .ummAlQura
    case "AE":
      .gulf
    case "US", "CA", "UK", "GB":
      .moonsightingCommittee
    case "KW":
      .kuwait
    case "BH", "OM", "YE", "QA":
      .qatar
    case "SG":
      .singapore
    case "IR":
      .tehran
    default:
      .muslimWorldLeague
    }
  }
}

nonisolated enum HighLatitudeRulePreference: Int {
  case middleOfTheNight = 0
  case seventhOfTheNight = 1
  case twilightAngle = 2

  /// SalahTimes' high-latitude rule.
  var rule: HighLatitudeRule {
    switch self {
    case .middleOfTheNight: .middleOfTheNight
    case .seventhOfTheNight: .seventhOfTheNight
    case .twilightAngle: .twilightAngle
    }
  }
}
