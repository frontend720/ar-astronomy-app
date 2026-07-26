import Foundation
import SatelliteKit

/// MVP scope: ISS/stations and Starlink only. Matches Celestrak's public GP group names,
/// so raw values double as query parameters in CelestrakClient.
public enum SatelliteCategory: String, Codable, Sendable, CaseIterable {
    case stations
    case starlink
}

/// A satellite/station tracked by the app, carrying its most recent TLE.
public struct TrackedObject: Identifiable, Sendable {
    public let id: UInt // NORAD catalog number
    public let name: String
    public let category: SatelliteCategory
    public let elements: Elements

    /// NORAD catalog number for the ISS (ZARYA) — used to pick it out of Celestrak's broader "stations" group.
    public static let issNoradID: UInt = 25544

    public init(name: String, category: SatelliteCategory, elements: Elements) {
        self.id = elements.noradIndex
        self.name = name
        self.category = category
        self.elements = elements
    }

    /// Launch year parsed from the TLE international designator (e.g. "1998-067A" -> 1998).
    /// This is the only "launch info" available without a second data source.
    public var launchYear: Int? {
        Int(elements.launchName.split(separator: "-").first ?? "")
    }
}
