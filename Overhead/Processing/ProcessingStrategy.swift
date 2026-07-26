import Foundation
import Metal

/// Detects device capabilities at runtime and decides whether image stacking
/// should happen locally on the GPU or be offloaded to the remote Python backend.
///
/// The two gates:
///   - RAM:   iOS reports physical memory via ProcessInfo. Astrophoto stacking
///            needs headroom for the accumulator buffer + one decoded RAW at a time.
///            ~6 GB physical gives ~4 GB usable after OS overhead — enough for
///            full-resolution stacks of 20-30 frames without hitting Jetsam.
///   - Metal: apple4 family = A11 Bionic (iPhone X/8) or later — the first
///            generation with a Neural Engine and the performance tier required
///            for the compute shaders that do alignment and blending.
///
/// Devices that fall below either threshold use RemotePythonPipeline instead.
struct ProcessingStrategy {
    enum Tier {
        case local   // GPU stacking on device — RAM ≥ 6 GB and apple4+ Metal
        case remote  // offload to backend — constrained device
    }

    let tier: Tier
    let physicalMemoryGB: Double
    let supportsApple4Family: Bool

    static let current = ProcessingStrategy()

    init() {
        let memGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        let metalDevice = MTLCreateSystemDefaultDevice()
        let apple4 = metalDevice?.supportsFamily(.apple4) ?? false

        physicalMemoryGB = memGB
        supportsApple4Family = apple4
        tier = (memGB >= 5.5 && apple4) ? .local : .remote
    }
}
