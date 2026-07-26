import SceneKit
import UIKit
import OverheadCore

/// Renders all above-horizon constellation stick-figure segments as a single
/// SceneKit line-primitive geometry — one draw call for all 88 constellations.
/// A second child node renders the star vertices as points, one draw call.
/// Rebuilt at most every 30 seconds since the sky rotates ~0.5°/min.
final class ConstellationOverlayNode: SCNNode {

    private lazy var starNode: SCNNode = {
        let n = SCNNode()
        addChildNode(n)
        return n
    }()

    func update(arcs: [ConstellationArc], distance: Float) {
        guard !arcs.isEmpty else {
            geometry = nil
            starNode.geometry = nil
            return
        }

        // MARK: Line geometry
        var lineVertices: [SCNVector3] = []
        var lineIndices: [Int32] = []
        lineVertices.reserveCapacity(arcs.count * 2)
        lineIndices.reserveCapacity(arcs.count * 2)

        for arc in arcs {
            let base = Int32(lineVertices.count)
            lineVertices.append(Self.scenePos(az: arc.startAzimuthDegrees, el: arc.startElevationDegrees, d: distance))
            lineVertices.append(Self.scenePos(az: arc.endAzimuthDegrees,   el: arc.endElevationDegrees,   d: distance))
            lineIndices.append(contentsOf: [base, base + 1])
        }

        let lineGeo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: lineVertices)],
            elements: [SCNGeometryElement(indices: lineIndices, primitiveType: .line)]
        )
        lineGeo.firstMaterial = Self.lineMaterial
        geometry = lineGeo

        // MARK: Star point geometry
        // Each arc endpoint is a real star position. Deduplicate by rounding az/el
        // to 2 decimal places — the same star appears as both ends of adjacent segments.
        var seen = Set<String>()
        var starVertices: [SCNVector3] = []

        for arc in arcs {
            for (az, el) in [(arc.startAzimuthDegrees, arc.startElevationDegrees),
                             (arc.endAzimuthDegrees,   arc.endElevationDegrees)] {
                let key = "\(Int(az * 100))_\(Int(el * 100))"
                guard seen.insert(key).inserted else { continue }
                starVertices.append(Self.scenePos(az: az, el: el, d: distance))
            }
        }

        let pointElement = SCNGeometryElement(
            indices: Array(Int32(0) ..< Int32(starVertices.count)),
            primitiveType: .point
        )
        pointElement.pointSize = 0.005
        pointElement.minimumPointScreenSpaceRadius = 2.0
        pointElement.maximumPointScreenSpaceRadius = 5.0

        let starGeo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: starVertices)],
            elements: [pointElement]
        )
        starGeo.firstMaterial = Self.starMaterial
        starNode.geometry = starGeo
    }

    // MARK: - Materials

    private static let lineMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 0.40)
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        return m
    }()

    private static let starMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.diffuse.contents  = UIColor(white: 1.0, alpha: 0.95)
        m.emission.contents = UIColor(red: 0.75, green: 0.90, blue: 1.0, alpha: 0.90)
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        return m
    }()

    // MARK: - Coordinate transform

    /// Az 0=N clockwise, El 0=horizon → scene +X=east, +Y=up, -Z=north.
    /// Matches the coordinate system used in SkyARView.Coordinator.position(for:distance:).
    private static func scenePos(az: Double, el: Double, d: Float) -> SCNVector3 {
        let az = Float(az) * .pi / 180
        let el = Float(el) * .pi / 180
        let h = d * cos(el)
        return SCNVector3(h * sin(az), d * sin(el), -h * cos(az))
    }
}
