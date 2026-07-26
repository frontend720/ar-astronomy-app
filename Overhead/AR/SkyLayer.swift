import Foundation

/// Which sky-overlay layers are visible in the AR view. Satellites always draw on top of
/// constellation lines when both are active — that's enforced via SceneKit `renderingOrder`
/// in SatelliteLabelNode/ConstellationOverlayNode (painter's-algorithm draw order), not by
/// occlusion/depth logic, since neither layer's material participates in depth testing.
enum SkyLayer: String, CaseIterable, Identifiable {
    case all = "All"
    case satellites = "Satellites"
    case constellations = "Constellations"

    var id: String { rawValue }

    var showsSatellites: Bool    { self != .constellations }
    var showsConstellations: Bool { self != .satellites }
    var showsPlanets: Bool        { self != .satellites }
    var showsMoon: Bool           { self != .satellites }

    var systemImage: String {
        switch self {
        case .all:            return "sparkles"
        case .satellites:     return "antenna.radiowaves.left.and.right"
        case .constellations: return "star.fill"
        }
    }

    var next: SkyLayer {
        let cases = SkyLayer.allCases
        return cases[(cases.firstIndex(of: self)! + 1) % cases.count]
    }
}
