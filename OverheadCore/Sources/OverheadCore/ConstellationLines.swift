import Foundation
import SatelliteKit

/// One line segment between two stars, already projected into the local Alt/Az
/// frame. Both endpoints are guaranteed above the horizon — segments that cross
/// or lie below are dropped so nothing renders underground in the AR scene.
public struct ConstellationArc: Sendable {
    public let startAzimuthDegrees: Double
    public let startElevationDegrees: Double
    public let endAzimuthDegrees: Double
    public let endElevationDegrees: Double
}

/// Parses a d3-celestial `constellations.lines.json` file and projects each
/// line segment from celestial RA/Dec into the observer's local Alt/Az frame.
///
/// Expected format: GeoJSON FeatureCollection of MultiLineString / LineString
/// features where coordinates are [RA_degrees, Dec_degrees] (0–360 / ±90).
/// Download from: https://github.com/ofrohn/d3-celestial/blob/master/data/constellations.lines.json
/// Add to the Xcode project as a resource (drag into the Overhead group, tick
/// "Add to targets: Overhead").
public enum ConstellationLines {

    /// The URL of the bundled constellation data, or nil if the package resource is missing.
    /// Exposed for debug diagnostics.
    public static var bundleURL: URL? {
        Bundle.module.url(forResource: "constellations", withExtension: "json")
    }

    /// Loads the bundled `constellations.json` from the OverheadCore package
    /// resource bundle — no Xcode app-target configuration required.
    public static func project(
        observer: ObserverLocation,
        at date: Date = Date()
    ) -> [ConstellationArc] {
        guard let url = bundleURL else { return [] }
        return project(from: url, observer: observer, at: date)
    }

    public static func project(
        from url: URL,
        observer: ObserverLocation,
        at date: Date = Date()
    ) -> [ConstellationArc] {
        guard let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(FeatureCollection.self, from: data)
        else { return [] }

        let site = (observer.latitudeDegrees, observer.longitudeDegrees)
        var arcs: [ConstellationArc] = []

        for feature in collection.features {
            for polyline in feature.geometry.polylines {
                for i in 0 ..< polyline.count - 1 {
                    let p0 = polyline[i], p1 = polyline[i + 1]
                    guard p0.count >= 2, p1.count >= 2 else { continue }

                    let s = azel(time: date, site: site, cele: (p0[0], p0[1]))
                    let e = azel(time: date, site: site, cele: (p1[0], p1[1]))
                    guard s.alt > 0, e.alt > 0 else { continue }

                    arcs.append(ConstellationArc(
                        startAzimuthDegrees: s.azi,
                        startElevationDegrees: s.alt,
                        endAzimuthDegrees: e.azi,
                        endElevationDegrees: e.alt
                    ))
                }
            }
        }

        return arcs
    }

    // MARK: - GeoJSON Decoding

    private struct FeatureCollection: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let geometry: Geometry
    }

    private struct Geometry: Decodable {
        /// Normalised to an array of polylines regardless of LineString vs MultiLineString.
        let polylines: [[[Double]]]

        private enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "LineString":
                polylines = [try c.decode([[Double]].self, forKey: .coordinates)]
            case "MultiLineString":
                polylines = try c.decode([[[Double]]].self, forKey: .coordinates)
            default:
                polylines = []
            }
        }
    }
}
