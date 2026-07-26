import UIKit

/// Top-level coordinator for astrophotography processing. At init time it reads
/// `ProcessingStrategy.current` and wires up either the local Metal pipeline or
/// the remote Python pipeline. Callers only ever talk to this class — the
/// underlying tier is transparent.
@MainActor
final class AstrophotographyEngine: ObservableObject {

    // MARK: - State

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: Error?
    @Published private(set) var result: UIImage?

    let strategy: ProcessingStrategy

    // MARK: - Private

    private let pipeline: any ImageProcessingPipeline

    // MARK: - Init

    init() {
        let s = ProcessingStrategy.current
        strategy = s

        switch s.tier {
        case .local:
            do {
                pipeline = try LocalMetalPipeline()
            } catch {
                // Metal initialisation failed at runtime — fall back gracefully.
                pipeline = RemotePythonPipeline() ?? FallbackErrorPipeline()
            }
        case .remote:
            pipeline = RemotePythonPipeline() ?? FallbackErrorPipeline()
        }
    }

    // MARK: - Public API

    /// Stacks the supplied RAW image URLs and stores the result in `result`.
    func processStack(images: [URL]) async {
        guard !images.isEmpty else { return }
        isProcessing = true
        lastError = nil
        result = nil

        do {
            result = try await pipeline.processStack(images: images)
        } catch {
            lastError = error
        }

        isProcessing = false
    }

    /// Writes the current `result` to the in-app gallery directory.
    /// Returns the saved file URL so the caller can confirm or display it.
    @discardableResult
    func saveResult() throws -> URL {
        guard let image = result else {
            throw ProcessingError.stackingFailed("No result to save")
        }
        let dir = Self.galleryDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "stack_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = dir.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            throw ProcessingError.stackingFailed("Failed to encode result as JPEG")
        }
        try data.write(to: url)
        return url
    }

    // MARK: - Gallery

    /// Shared gallery directory inside the app's Documents folder.
    static var galleryDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AstroGallery")
    }

    // MARK: - Diagnostics

    var tierDescription: String {
        switch strategy.tier {
        case .local:  return "Local (Metal · \(String(format: "%.1f", strategy.physicalMemoryGB)) GB)"
        case .remote: return "Remote (Python backend · \(String(format: "%.1f", strategy.physicalMemoryGB)) GB)"
        }
    }
}

// MARK: - FallbackErrorPipeline

/// A last-resort pipeline used when neither local Metal nor the configured
/// remote backend URL is available. Always throws so the UI can surface a
/// meaningful error instead of silently doing nothing.
private final class FallbackErrorPipeline: ImageProcessingPipeline {
    func processStack(images: [URL]) async throws -> UIImage {
        throw ProcessingError.networkUnavailable
    }
}
