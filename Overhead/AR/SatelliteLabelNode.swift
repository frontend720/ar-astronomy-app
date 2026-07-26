import SceneKit
import UIKit
import OverheadCore

enum LabelDisplayMode: Equatable {
    case capsule
    case expanded
}

/// Billboarded satellite annotation with two display modes:
///   capsule  — compact pill for off-aim satellites (● Name)
///   expanded — full glass card + hairline stem for on-aim satellites
final class SatelliteLabelNode: SCNNode {
    private(set) var snapshot: SatelliteSnapshot
    private var displayMode: LabelDisplayMode = .capsule
    private var isSelected: Bool = false

    private let dotMaterial = SCNMaterial()
    private let cardNode = SCNNode()
    private let stemNode = SCNNode()

    private static let dotRadius:     Float   = 0.40
    private static let stemHeight:    Float   = 1.60
    private static let hitTargetSize: CGFloat = 6.0

    /// Neither this node's materials nor ConstellationOverlayNode's participate in depth
    /// testing, so draw order is decided purely by renderingOrder (painter's algorithm).
    /// Must stay above ConstellationOverlayNode's so satellites always render on top,
    /// regardless of which SkyLayer combination is active.
    private static let renderingOrder = 100

    // Plane heights in scene meters. At SkyARView's 50 m label distance with
    // ~60° FOV: 1 m ≈ 7.3 pt on screen → expanded 4.5 m ≈ 33 pt, capsule 2.4 m ≈ 18 pt.
    private static let expandedPlaneH: CGFloat = 4.5
    private static let capsulePlaneH:  CGFloat = 2.4

    init(snapshot: SatelliteSnapshot) {
        self.snapshot = snapshot
        super.init()

        // Dot marker at node origin (satellite's sky direction)
        let sphere = SCNSphere(radius: CGFloat(Self.dotRadius))
        dotMaterial.diffuse.contents = Self.accentColor(for: snapshot, selected: false)
        dotMaterial.lightingModel = .constant
        sphere.materials = [dotMaterial]
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.renderingOrder = Self.renderingOrder
        addChildNode(sphereNode)

        // Hairline stem connecting dot to expanded card (hidden in capsule mode)
        let stemGeo = SCNPlane(width: 0.14, height: CGFloat(Self.stemHeight))
        let stemMat = SCNMaterial()
        stemMat.diffuse.contents = UIColor(white: 1.0, alpha: 0.22)
        stemMat.lightingModel = .constant
        stemMat.isDoubleSided = true
        stemMat.writesToDepthBuffer = false
        stemMat.readsFromDepthBuffer = false
        stemGeo.materials = [stemMat]
        stemNode.geometry = stemGeo
        stemNode.position = SCNVector3(0, Self.dotRadius + Self.stemHeight / 2, 0)
        stemNode.opacity = 0
        stemNode.renderingOrder = Self.renderingOrder
        addChildNode(stemNode)

        // Card image plane (repositioned + re-textured on mode switch)
        cardNode.renderingOrder = Self.renderingOrder
        addChildNode(cardNode)

        // Invisible oversized hit target so taps register on the dot
        let hitTarget = SCNPlane(width: Self.hitTargetSize, height: Self.hitTargetSize)
        let hitMat = SCNMaterial()
        hitMat.diffuse.contents = UIColor.clear
        hitMat.isDoubleSided = true
        hitMat.writesToDepthBuffer = false
        hitMat.readsFromDepthBuffer = false
        hitTarget.materials = [hitMat]
        addChildNode(SCNNode(geometry: hitTarget))

        constraints = [SCNBillboardConstraint()]
        applyMode(.capsule, animated: false)

        // Ease new labels into the scene rather than snapping on.
        opacity = 0
        scale = SCNVector3(0.92, 0.92, 0.92)
        let appear = SCNAction.group([
            SCNAction.fadeIn(duration: 0.22),
            SCNAction.scale(to: 1.0, duration: 0.22),
        ])
        appear.timingMode = .easeOut
        runAction(appear)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(snapshot: SatelliteSnapshot) {
        self.snapshot = snapshot
    }

    func setDisplayMode(_ mode: LabelDisplayMode) {
        guard mode != displayMode else { return }
        applyMode(mode, animated: true)
    }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected
        dotMaterial.diffuse.contents = Self.accentColor(for: snapshot, selected: isSelected)
        applyMode(displayMode, animated: false)
    }

    // MARK: - Mode Application

    private func applyMode(_ mode: LabelDisplayMode, animated: Bool) {
        displayMode = mode
        let accent = Self.accentColor(for: snapshot, selected: isSelected)

        let image: UIImage
        let planeH: CGFloat
        let cardY: Float
        let showStem: Bool

        switch mode {
        case .capsule:
            image = Self.capsuleImage(for: snapshot, accent: accent)
            planeH = Self.capsulePlaneH
            cardY = Self.dotRadius + Float(planeH) / 2 + 0.20
            showStem = false

        case .expanded:
            image = Self.expandedImage(for: snapshot, accent: accent)
            planeH = Self.expandedPlaneH
            cardY = Self.dotRadius + Self.stemHeight + Float(planeH) / 2
            showStem = true
        }

        let aspect = image.size.width / image.size.height
        let plane = SCNPlane(width: planeH * aspect, height: planeH)
        plane.materials = [Self.planeMaterial(image: image)]

        if animated {
            cardNode.runAction(SCNAction.sequence([
                SCNAction.fadeOut(duration: 0.12),
                SCNAction.run { node in
                    node.geometry = plane
                    node.position = SCNVector3(0, cardY, 0)
                },
                SCNAction.fadeIn(duration: 0.15),
            ]), forKey: "modeTransition")

            stemNode.runAction(
                showStem ? SCNAction.fadeIn(duration: 0.20) : SCNAction.fadeOut(duration: 0.12),
                forKey: "stemTransition"
            )
        } else {
            cardNode.geometry = plane
            cardNode.position = SCNVector3(0, cardY, 0)
            stemNode.opacity = showStem ? 1 : 0
        }
    }

    // MARK: - Helpers

    private static func planeMaterial(image: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.isDoubleSided = true
        m.lightingModel = .constant
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        return m
    }

    private static func accentColor(for snapshot: SatelliteSnapshot, selected: Bool) -> UIColor {
        if selected { return UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1.0) }  // vivid cyan
        switch snapshot.object.category {
        case .stations: return UIColor(red: 1.00, green: 0.84, blue: 0.20, alpha: 1)   // warm gold
        case .starlink:  return UIColor(red: 0.65, green: 0.85, blue: 1.00, alpha: 1)  // pale ice blue
        }
    }

    // MARK: - Image Rendering

    private static func capsuleImage(for snapshot: SatelliteSnapshot, accent: UIColor) -> UIImage {
        let name = snapshot.object.name

        let font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
        ]
        let textSize = (name as NSString).size(withAttributes: attrs)

        let dotD: CGFloat   = 11
        let dotGap: CGFloat = 8
        let hPad: CGFloat   = 16
        let vPad: CGFloat   = 11
        let w = hPad + dotD + dotGap + textSize.width + hPad
        let h = max(textSize.height, dotD) + vPad * 2
        let size = CGSize(width: w, height: h)

        return UIGraphicsImageRenderer(size: size).image { _ in
            let bounds = CGRect(origin: .zero, size: size)

            UIColor(white: 0.06, alpha: 0.80).setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: h / 2).fill()

            UIColor(white: 1.0, alpha: 0.12).setStroke()
            let border = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: (h - 1) / 2)
            border.lineWidth = 1
            border.stroke()

            accent.setFill()
            UIBezierPath(ovalIn: CGRect(x: hPad, y: (h - dotD) / 2, width: dotD, height: dotD)).fill()

            (name as NSString).draw(at: CGPoint(x: hPad + dotD + dotGap, y: vPad), withAttributes: attrs)
        }
    }

    private static func expandedImage(for snapshot: SatelliteSnapshot, accent: UIColor) -> UIImage {
        let isStation = snapshot.object.category == .stations

        let name     = snapshot.object.name
        let subtitle = isStation ? "Space Station" : "LEO · Starlink"

        let nameFont = UIFont.systemFont(ofSize: 28, weight: .semibold)
        let subFont  = UIFont.systemFont(ofSize: 19, weight: .regular)

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: nameFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.94),
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: subFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.56),
        ]

        let nameSize = (name     as NSString).size(withAttributes: nameAttrs)
        let subSize  = (subtitle as NSString).size(withAttributes: subAttrs)

        let hPad: CGFloat    = 18
        let vPad: CGFloat    = 13
        let lineGap: CGFloat = 5

        let w = max(nameSize.width, subSize.width) + hPad * 2
        let h = nameSize.height + lineGap + subSize.height + vPad * 2
        let size = CGSize(width: w, height: h)

        return UIGraphicsImageRenderer(size: size).image { _ in
            let bounds = CGRect(origin: .zero, size: size)

            UIColor(white: 0.06, alpha: 0.82).setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: 16).fill()

            accent.withAlphaComponent(0.22).setStroke()
            let border = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 15.5)
            border.lineWidth = 1
            border.stroke()

            (name as NSString).draw(
                at: CGPoint(x: hPad, y: vPad),
                withAttributes: nameAttrs
            )
            (subtitle as NSString).draw(
                at: CGPoint(x: hPad, y: vPad + nameSize.height + lineGap),
                withAttributes: subAttrs
            )
        }
    }
}
