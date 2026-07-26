import SceneKit
import UIKit
import OverheadCore

/// Billboarded AR node representing one naked-eye planet: a coloured glowing
/// sphere scaled to visual magnitude plus a subtle name label above it.
/// Rendering order 50 places it above constellation lines (−100) but below
/// satellite labels (100).
final class PlanetNode: SCNNode {

    let planetName: String
    private(set) var snapshot: PlanetSnapshot
    private static let renderingOrder = 50

    init(snapshot: PlanetSnapshot) {
        self.planetName = snapshot.name
        self.snapshot = snapshot
        super.init()

        let radius   = Self.sphereRadius(for: snapshot.magnitude)
        let color    = UIColor(red:   CGFloat(snapshot.colorR),
                               green: CGFloat(snapshot.colorG),
                               blue:  CGFloat(snapshot.colorB),
                               alpha: 1.0)

        // Glowing sphere at the node origin
        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = 10
        let dotMat = SCNMaterial()
        dotMat.diffuse.contents  = color
        dotMat.emission.contents = color
        dotMat.lightingModel = .constant
        dotMat.writesToDepthBuffer = false
        dotMat.readsFromDepthBuffer = false
        sphere.materials = [dotMat]
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.renderingOrder = Self.renderingOrder
        addChildNode(sphereNode)

        // Name label plane, sitting just above the sphere
        let labelImage = Self.labelImage(name: snapshot.name, color: color)
        let aspect  = labelImage.size.width / labelImage.size.height
        let labelH: CGFloat = 1.2
        let labelPlane = SCNPlane(width: labelH * aspect, height: labelH)
        let labelMat = SCNMaterial()
        labelMat.diffuse.contents  = labelImage
        labelMat.lightingModel = .constant
        labelMat.isDoubleSided = true
        labelMat.writesToDepthBuffer = false
        labelMat.readsFromDepthBuffer = false
        labelPlane.materials = [labelMat]
        let labelNode = SCNNode(geometry: labelPlane)
        labelNode.position = SCNVector3(0, radius + Float(labelH) / 2 + 0.10, 0)
        labelNode.renderingOrder = Self.renderingOrder
        addChildNode(labelNode)

        constraints = [SCNBillboardConstraint()]
        renderingOrder = Self.renderingOrder

        opacity = 0
        let appear = SCNAction.fadeIn(duration: 0.28)
        appear.timingMode = .easeOut
        runAction(appear)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(snapshot: PlanetSnapshot) {
        self.snapshot = snapshot
    }

    // MARK: - Helpers

    /// Maps visual magnitude to sphere radius in scene units.
    /// At sky radius 50, 1 scene unit ≈ 7.3 pt on screen.
    /// Venus (−4.4) → 0.42 unit (~6 pt diameter); Saturn (+0.5) → 0.25 unit (~4 pt).
    private static func sphereRadius(for magnitude: Double) -> Float {
        let clamped = max(-5.0, min(3.0, magnitude))
        return Float(max(0.12, min(0.42, 0.28 - 0.05 * clamped)))
    }

    private static func labelImage(name: String, color: UIColor) -> UIImage {
        let font  = UIFont.systemFont(ofSize: 20, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.72),
        ]
        let textSize = (name as NSString).size(withAttributes: attrs)
        let hPad: CGFloat = 8, vPad: CGFloat = 4
        let size = CGSize(width: textSize.width + hPad * 2,
                          height: textSize.height + vPad * 2)

        return UIGraphicsImageRenderer(size: size).image { _ in
            (name as NSString).draw(at: CGPoint(x: hPad, y: vPad),
                                    withAttributes: attrs)
        }
    }
}
