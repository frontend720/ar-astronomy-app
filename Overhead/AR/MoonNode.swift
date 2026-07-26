import SceneKit
import UIKit
import OverheadCore

/// Billboarded AR node representing the Moon: a larger silver-white glowing sphere
/// with a name label above it. Sits at the same rendering order as planets (50).
final class MoonNode: SCNNode {

    private static let renderingOrder = 50
    private(set) var snapshot: MoonSnapshot

    init(snapshot: MoonSnapshot) {
        self.snapshot = snapshot
        super.init()

        let radius: CGFloat = 0.65
        let color = UIColor(red: 0.92, green: 0.92, blue: 0.96, alpha: 1.0)

        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 16
        let dotMat = SCNMaterial()
        dotMat.diffuse.contents  = color
        dotMat.emission.contents = UIColor(red: 0.70, green: 0.70, blue: 0.75, alpha: 1.0)
        dotMat.lightingModel = .constant
        dotMat.writesToDepthBuffer = false
        dotMat.readsFromDepthBuffer = false
        sphere.materials = [dotMat]
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.renderingOrder = Self.renderingOrder
        addChildNode(sphereNode)

        let labelImage = Self.labelImage()
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
        labelNode.position = SCNVector3(0, Float(radius) + Float(labelH) / 2 + 0.10, 0)
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

    func update(snapshot: MoonSnapshot) {
        self.snapshot = snapshot
    }

    private static func labelImage() -> UIImage {
        let font  = UIFont.systemFont(ofSize: 20, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.72),
        ]
        let textSize = ("Moon" as NSString).size(withAttributes: attrs)
        let hPad: CGFloat = 8, vPad: CGFloat = 4
        let size = CGSize(width: textSize.width + hPad * 2,
                          height: textSize.height + vPad * 2)
        return UIGraphicsImageRenderer(size: size).image { _ in
            ("Moon" as NSString).draw(at: CGPoint(x: hPad, y: vPad),
                                      withAttributes: attrs)
        }
    }
}
