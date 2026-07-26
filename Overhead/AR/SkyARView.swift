import SwiftUI
import ARKit
import SceneKit
import OverheadCore

/// AR camera view that labels tracked satellites and draws constellation
/// stick figures in real time.
///
/// Uses `.gravityAndHeading` world alignment so the scene's compass directions
/// are fixed to true north/east/up regardless of how the device is held —
/// satellite azimuth/elevation from SatelliteKit map directly onto scene
/// coordinates without tracking device orientation by hand.
///
/// Note: ARKit requires real camera hardware and does not run in the iOS
/// Simulator — this view can only be verified on a physical device.
struct SkyARView: UIViewRepresentable {
    let snapshots: [SatelliteSnapshot]
    let observer: ObserverLocation?
    let selectedID: UInt?
    let layer: SkyLayer
    let onSelect: (SatelliteSnapshot) -> Void
    let onSelectPlanet: (PlanetSnapshot) -> Void
    let onSelectMoon: (MoonSnapshot) -> Void

    /// Fixed render distance for all sky objects, in meters. Real satellite
    /// range is hundreds of kilometers — what matters in AR is the correct
    /// azimuth/elevation direction, so everything sits on a sphere at this
    /// distance. Constellation lines use the same distance so they sit on
    /// the same virtual sphere as the satellite labels.
    private static let skyRadius: Float = 50

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = context.coordinator
        view.scene = SCNScene()
        view.autoenablesDefaultLighting = true

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        view.session.run(config)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tap)
        context.coordinator.arView = view

        // Painter's-algorithm draw order: neither layer's material participates in depth
        // testing (see ConstellationOverlayNode / SatelliteLabelNode), so whichever renders
        // later wins visually wherever they overlap. Constellations draw first/underneath;
        // satellite labels always draw after/on top, in every combined layer state.
        context.coordinator.constellationNode.renderingOrder = -100
        view.scene.rootNode.addChildNode(context.coordinator.constellationNode)

        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onSelectPlanet = onSelectPlanet
        context.coordinator.onSelectMoon = onSelectMoon
        context.coordinator.updateSatellites(snapshots: snapshots, selectedID: selectedID, observer: observer, in: uiView.scene, radius: Self.skyRadius, isVisible: layer.showsSatellites)
        context.coordinator.updateConstellations(observer: observer, in: uiView.scene, radius: Self.skyRadius, isVisible: layer.showsConstellations)
        context.coordinator.updatePlanets(observer: observer, in: uiView.scene, radius: Self.skyRadius, isVisible: layer.showsPlanets)
        context.coordinator.updateMoon(observer: observer, in: uiView.scene, radius: Self.skyRadius, isVisible: layer.showsMoon)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARSCNView?
        var onSelect: ((SatelliteSnapshot) -> Void)?
        var onSelectPlanet: ((PlanetSnapshot) -> Void)?
        var onSelectMoon: ((MoonSnapshot) -> Void)?

        private var nodesByID: [UInt: SatelliteLabelNode] = [:]

        let constellationNode = ConstellationOverlayNode()
        private var lastConstellationUpdate: Date = .distantPast
        private let constellationRefreshInterval: TimeInterval = 30

        private var planetNodesByName: [String: PlanetNode] = [:]
        private var lastPlanetUpdate: Date = .distantPast
        private let planetRefreshInterval: TimeInterval = 30

        private var moonNode: MoonNode?
        private var lastMoonUpdate: Date = .distantPast
        private let moonRefreshInterval: TimeInterval = 30

        /// Must match SatelliteTrackingService.positionRefreshInterval so the
        /// forward-prediction animation lands at the right place when the next
        /// snapshot arrives.
        private static let positionAnimationInterval: TimeInterval = 2.0

        // MARK: - Satellite labels

        func updateSatellites(snapshots: [SatelliteSnapshot], selectedID: UInt?, observer: ObserverLocation?, in scene: SCNScene, radius: Float, isVisible: Bool) {
            let visible = snapshots.filter { $0.look.isAboveHorizon }
            let visibleIDs = Set(visible.map(\.id))

            for (id, node) in nodesByID where !visibleIDs.contains(id) {
                node.removeFromParentNode()
                nodesByID.removeValue(forKey: id)
            }

            for snapshot in visible {
                let currentPosition = Self.position(for: snapshot.look, distance: radius)

                // Predict where the satellite will be at the end of this animation interval
                // so the node glides forward continuously instead of snapping each tick.
                let futurePosition: SCNVector3
                if let observer,
                   let future = try? SatellitePosition.snapshot(
                       for: snapshot.object,
                       observer: observer,
                       at: snapshot.at.addingTimeInterval(Self.positionAnimationInterval)
                   ),
                   future.look.isAboveHorizon {
                    futurePosition = Self.position(for: future.look, distance: radius)
                } else {
                    futurePosition = currentPosition
                }

                if let node = nodesByID[snapshot.id] {
                    node.removeAction(forKey: "orbit")
                    node.position = currentPosition
                    node.update(snapshot: snapshot)
                } else {
                    let node = SatelliteLabelNode(snapshot: snapshot)
                    node.position = currentPosition
                    scene.rootNode.addChildNode(node)
                    nodesByID[snapshot.id] = node
                }

                // Glide to the predicted future position; action is cancelled and restarted
                // on each update tick so there's no accumulated drift.
                nodesByID[snapshot.id]?.runAction(
                    SCNAction.move(to: futurePosition, duration: Self.positionAnimationInterval),
                    forKey: "orbit"
                )
            }

            // Apply selection state and layer visibility first so the mode decision below can
            // account for it. Positions/animation above still run even while hidden, so
            // toggling the layer back on shows live, not stale, satellite positions.
            // SceneKit hit-testing ignores hidden nodes by default, so this also naturally
            // makes hidden satellites untappable — no separate gating needed for that.
            for (_, node) in nodesByID {
                node.setSelected(node.snapshot.id == selectedID)
                node.isHidden = !isVisible
            }

            // Expand labels near the camera aim point; collapse the rest to capsules.
            // ISS and selected satellites are always expanded.
            guard let arView else { return }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let expandThreshold: CGFloat = 150   // pt from screen center

            for (_, node) in nodesByID {
                let isStation  = node.snapshot.object.category == .stations
                let isSelected = node.snapshot.id == selectedID
                let sp = arView.projectPoint(node.worldPosition)
                let onScreen = sp.z > 0 && sp.z < 1
                let dist = hypot(CGFloat(sp.x) - center.x, CGFloat(sp.y) - center.y)
                node.setDisplayMode(isStation || isSelected || (onScreen && dist < expandThreshold) ? .expanded : .capsule)
            }
        }

        // MARK: - Constellation lines

        func updateConstellations(observer: ObserverLocation?, in scene: SCNScene, radius: Float, isVisible: Bool) {
            constellationNode.isHidden = !isVisible
            // Skip the projection work entirely while this layer isn't shown — no point
            // recomputing all 88 constellations' line segments every 30s for a hidden layer.
            guard isVisible,
                  let observer,
                  Date().timeIntervalSince(lastConstellationUpdate) > constellationRefreshInterval
            else { return }
            lastConstellationUpdate = Date()

            let arcs = ConstellationLines.project(observer: observer)
            constellationNode.update(arcs: arcs, distance: radius)
        }

        // MARK: - Planets

        func updatePlanets(observer: ObserverLocation?, in scene: SCNScene, radius: Float, isVisible: Bool) {
            for (_, node) in planetNodesByName { node.isHidden = !isVisible }
            guard isVisible,
                  let observer,
                  Date().timeIntervalSince(lastPlanetUpdate) > planetRefreshInterval
            else { return }
            lastPlanetUpdate = Date()

            let snapshots = PlanetPosition.snapshots(observer: observer)

            for snapshot in snapshots {
                let pos = Self.planetPosition(az: snapshot.azimuthDegrees,
                                              el: snapshot.elevationDegrees,
                                              distance: radius)
                if let node = planetNodesByName[snapshot.name] {
                    node.position = pos
                    node.update(snapshot: snapshot)
                    node.isHidden = !snapshot.isAboveHorizon || !isVisible
                } else {
                    let node = PlanetNode(snapshot: snapshot)
                    node.position = pos
                    node.isHidden = !snapshot.isAboveHorizon
                    scene.rootNode.addChildNode(node)
                    planetNodesByName[snapshot.name] = node
                }
            }
        }

        private static func planetPosition(az: Double, el: Double, distance: Float) -> SCNVector3 {
            let az = Float(az) * .pi / 180
            let el = Float(el) * .pi / 180
            let h  = distance * cos(el)
            return SCNVector3(h * sin(az), distance * sin(el), -h * cos(az))
        }

        // MARK: - Tap handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = gesture.location(in: arView)
            let hits = arView.hitTest(point, options: [.searchMode: NSNumber(value: 1)])

            if let hit = hits.first(where: { $0.node is SatelliteLabelNode || $0.node.parent is SatelliteLabelNode }) {
                let node = (hit.node as? SatelliteLabelNode) ?? (hit.node.parent as? SatelliteLabelNode)
                if let snapshot = node?.snapshot { onSelect?(snapshot) }
                return
            }

            if let hit = hits.first(where: { $0.node is PlanetNode || $0.node.parent is PlanetNode }) {
                let node = (hit.node as? PlanetNode) ?? (hit.node.parent as? PlanetNode)
                if let snapshot = node?.snapshot { onSelectPlanet?(snapshot) }
                return
            }

            if let hit = hits.first(where: { $0.node is MoonNode || $0.node.parent is MoonNode }) {
                let node = (hit.node as? MoonNode) ?? (hit.node.parent as? MoonNode)
                if let snapshot = node?.snapshot { onSelectMoon?(snapshot) }
            }
        }

        // MARK: - Moon

        func updateMoon(observer: ObserverLocation?, in scene: SCNScene, radius: Float, isVisible: Bool) {
            moonNode?.isHidden = !isVisible
            guard isVisible,
                  let observer,
                  Date().timeIntervalSince(lastMoonUpdate) > moonRefreshInterval
            else { return }
            lastMoonUpdate = Date()

            let snapshot = MoonPosition.snapshot(observer: observer)
            let pos = Self.planetPosition(az: snapshot.azimuthDegrees,
                                          el: snapshot.elevationDegrees,
                                          distance: radius)
            if let node = moonNode {
                node.position = pos
                node.update(snapshot: snapshot)
                node.isHidden = !snapshot.isAboveHorizon
            } else {
                let node = MoonNode(snapshot: snapshot)
                node.position = pos
                node.isHidden = !snapshot.isAboveHorizon
                scene.rootNode.addChildNode(node)
                moonNode = node
            }
        }

        /// Az 0=N clockwise, El 0=horizon → scene +X=east, +Y=up, -Z=north.
        private static func position(for look: LookAngle, distance: Float) -> SCNVector3 {
            let az = Float(look.azimuthDegrees) * .pi / 180
            let el = Float(look.elevationDegrees) * .pi / 180
            let h = distance * cos(el)
            return SCNVector3(h * sin(az), distance * sin(el), -h * cos(az))
        }
    }
}
