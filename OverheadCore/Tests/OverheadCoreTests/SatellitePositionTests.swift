import XCTest
import SatelliteKit
@testable import OverheadCore

final class SatellitePositionTests: XCTestCase {
    // A real ISS TLE pulled from Celestrak. Propagating at its own epoch (rather than "now")
    // keeps the test's expected values correct regardless of how stale this fixture becomes.
    let line0 = "ISS (ZARYA)"
    let line1 = "1 25544U 98067A   26205.47558714  .00010646  00000+0  20005-3 0  9992"
    let line2 = "2 25544  51.6316 115.5643 0006921 332.7863  27.2762 15.49141208577537"

    func makeObject() throws -> TrackedObject {
        let elements = try Elements(line0, line1, line2)
        return TrackedObject(name: elements.commonName, category: .stations, elements: elements)
    }

    func testAltitudeAndSpeedAreLowEarthOrbit() throws {
        let object = try makeObject()
        let epoch = Date(ds1950: object.elements.t₀)
        let observer = ObserverLocation(latitudeDegrees: 40.0, longitudeDegrees: -75.0)

        let snapshot = try SatellitePosition.snapshot(for: object, observer: observer, at: epoch)

        XCTAssertEqual(snapshot.altitudeKm, 420, accuracy: 60)
        XCTAssertGreaterThan(snapshot.speedKmPerSec, 6.5)
        XCTAssertLessThan(snapshot.speedKmPerSec, 8.5)
        XCTAssertGreaterThanOrEqual(snapshot.look.azimuthDegrees, 0)
        XCTAssertLessThanOrEqual(snapshot.look.azimuthDegrees, 360)
        XCTAssertGreaterThanOrEqual(snapshot.look.elevationDegrees, -90)
        XCTAssertLessThanOrEqual(snapshot.look.elevationDegrees, 90)
    }

    func testLaunchYearParsedFromInternationalDesignator() throws {
        let object = try makeObject()
        XCTAssertEqual(object.launchYear, 1998)
        XCTAssertEqual(object.id, TrackedObject.issNoradID)
    }

    func testSnapshotsBatchSkipsNothingForValidCatalog() throws {
        let object = try makeObject()
        let observer = ObserverLocation(latitudeDegrees: 51.5, longitudeDegrees: -0.1)

        let snapshots = SatellitePosition.snapshots(for: [object], observer: observer)

        XCTAssertEqual(snapshots.count, 1)
    }
}
