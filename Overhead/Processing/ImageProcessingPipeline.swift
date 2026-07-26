import UIKit

/// Common interface for both the local Metal pipeline and the remote Python pipeline.
/// ViewModels and UI call this without knowing which path is active.
protocol ImageProcessingPipeline: AnyObject {
    /// Stacks and aligns `images` into a single processed master frame.
    /// - Parameter images: File URLs pointing to the source frames (RAW or JPEG).
    /// - Returns: The stacked, aligned, noise-reduced output image.
    func processStack(images: [URL]) async throws -> UIImage
}

enum ProcessingError: LocalizedError {
    case metalUnavailable
    case insufficientMemory
    case stackingFailed(String)
    case networkUnavailable
    case uploadFailed(String)
    case remoteJobFailed(String)

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:        return "Metal GPU is not available on this device."
        case .insufficientMemory:      return "Not enough memory to process this stack locally."
        case .stackingFailed(let msg): return "Stacking failed: \(msg)"
        case .networkUnavailable:      return "Network is required for remote processing."
        case .uploadFailed(let msg):   return "Upload failed: \(msg)"
        case .remoteJobFailed(let msg):return "Remote job failed: \(msg)"
        }
    }
}
