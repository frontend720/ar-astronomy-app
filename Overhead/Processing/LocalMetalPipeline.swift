import UIKit
import Metal

/// Processes image stacks entirely on-device using Metal compute shaders.
/// Only instantiated when ProcessingStrategy.current.tier == .local
/// (RAM ≥ 6 GB and apple4+ Metal family).
///
/// Implementation plan (not yet built):
///   1. Decode one RAW frame at a time into a float16 MTLTexture.
///   2. Align it to the reference frame using a custom Metal compute shader
///      that does sub-pixel phase-correlation.
///   3. Blend it into the accumulator MTLTexture (running mean).
///   4. Release the input texture and repeat — only two textures in GPU memory
///      at once (accumulator + current frame), keeping peak RSS predictable.
///   5. Apply noise reduction and histogram stretch in a final pass.
///
/// Memory discipline: each source frame is loaded inside an @autoreleasepool
/// block and released before the next frame loads, preventing the iOS Jetsam
/// reaper from killing the app mid-stack.
final class LocalMetalPipeline: ImageProcessingPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ProcessingError.metalUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw ProcessingError.metalUnavailable
        }
        self.device = device
        self.commandQueue = queue
    }

    func processStack(images: [URL]) async throws -> UIImage {
        guard !images.isEmpty else {
            throw ProcessingError.stackingFailed("No input frames provided.")
        }
        // TODO: implement iterative RAW decode → align → blend loop using Metal shaders.
        throw ProcessingError.stackingFailed("Metal pipeline is not yet implemented.")
    }
}
