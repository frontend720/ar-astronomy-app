import Foundation
import SatelliteKit

/// Ground observer position. Altitude defaults to sea level — GPS altitude is unreliable enough
/// that it's not worth plumbing through for an AR overlay where a few hundred meters of error
/// in *observer* altitude is negligible next to hundreds of kilometers of satellite range.
public struct ObserverLocation: Sendable {
    public let latitudeDegrees: Double
    public let longitudeDegrees: Double
    public let altitudeMeters: Double

    public init(latitudeDegrees: Double, longitudeDegrees: Double, altitudeMeters: Double = 0) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.altitudeMeters = altitudeMeters
    }

    var latLonAlt: LatLonAlt {
        LatLonAlt(latitudeDegrees, longitudeDegrees, altitudeMeters / 1000.0)
    }
}

/// Where a satellite appears relative to an observer, in the local horizon frame —
/// exactly what's needed to place an AR label against device heading/pitch.
public struct LookAngle: Sendable {
    public let azimuthDegrees: Double   // 0=North, clockwise
    public let elevationDegrees: Double // 0=horizon, 90=zenith
    public let rangeKm: Double

    public var isAboveHorizon: Bool { elevationDegrees > 0 }
}

public struct SatelliteSnapshot: Identifiable, Sendable {
    public let object: TrackedObject
    public let look: LookAngle
    public let altitudeKm: Double
    public let speedKmPerSec: Double
    public let at: Date

    public var id: UInt { object.id }
}

public enum SatellitePositionError: Error, Sendable {
    case propagationFailed
}

/// Thin wrapper around SatelliteKit's SGP4/SDP4 propagator, translating its ECI-frame API
/// into the observer-relative look angles and info-card fields the app actually needs.
public enum SatellitePosition {

    public static func snapshot(
        for object: TrackedObject,
        observer: ObserverLocation,
        at date: Date = Date()
    ) throws -> SatelliteSnapshot {
        let satellite = Satellite(withTLE: object.elements)
        let jd = date.julianDate

        do {
            let top = try satellite.topPosition(julianDays: jd, observer: observer.latLonAlt)
            let geo = try satellite.geoPosition(julianDays: jd)
            let velocity = try satellite.velocity(julianDays: jd)
            let speedKmPerSec = (velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z).squareRoot()

            return SatelliteSnapshot(
                object: object,
                look: LookAngle(azimuthDegrees: top.azim, elevationDegrees: top.elev, rangeKm: top.dist),
                altitudeKm: geo.alt,
                speedKmPerSec: speedKmPerSec,
                at: date
            )
        } catch {
            throw SatellitePositionError.propagationFailed
        }
    }

    /// Snapshots for every object in the catalog, silently dropping any whose propagation fails
    /// (e.g. a stale/decayed TLE) rather than failing the whole batch.
    public static func snapshots(
        for objects: [TrackedObject],
        observer: ObserverLocation,
        at date: Date = Date()
    ) -> [SatelliteSnapshot] {
        objects.compactMap { try? snapshot(for: $0, observer: observer, at: date) }
    }
}
