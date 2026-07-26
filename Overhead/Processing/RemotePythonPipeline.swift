import UIKit

/// Offloads image stacking to the Python backend for devices that lack the RAM
/// or Metal compute tier for local processing. The flow is:
///   1. Upload raw assets to object storage (S3 / R2)
///   2. POST a job request to the backend worker
///   3. Poll the job status endpoint until done or failed
///   4. Download the resulting stacked master TIFF / JPEG
///   5. Return a UIImage to the caller
///
/// None of this is implemented yet — the pipeline protocol scaffold is in place
/// so the engine can select this path at runtime without knowing the internals.
final class RemotePythonPipeline: ImageProcessingPipeline {

    // MARK: - Configuration

    /// Base URL for the Cloudflare Worker backend (set from project config / Info.plist).
    private let workerBaseURL: URL

    /// Maximum time to wait for a remote job before giving up.
    private let jobTimeoutSeconds: TimeInterval = 300

    /// How often to poll the job status endpoint.
    private let pollIntervalSeconds: TimeInterval = 5

    // MARK: - Init

    init(workerBaseURL: URL) {
        self.workerBaseURL = workerBaseURL
    }

    /// Convenience initialiser that reads `BackendWorkerURL` from Info.plist.
    convenience init?() {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "BackendWorkerURL") as? String,
              let url = URL(string: urlString)
        else { return nil }
        self.init(workerBaseURL: url)
    }

    // MARK: - ImageProcessingPipeline

    func processStack(images: [URL]) async throws -> UIImage {
        // TODO: Implement full remote pipeline:
        //
        // Step 1 — Upload
        //   let assetKeys = try await uploadAssets(images)
        //
        // Step 2 — Submit job
        //   let jobID = try await submitJob(assetKeys: assetKeys)
        //
        // Step 3 — Poll for completion
        //   let resultKey = try await pollJob(id: jobID)
        //
        // Step 4 — Download result
        //   let resultImage = try await downloadResult(key: resultKey)
        //   return resultImage

        throw ProcessingError.remoteJobFailed("RemotePythonPipeline not yet implemented")
    }

    // MARK: - Private helpers (stubs)

    private func uploadAssets(_ urls: [URL]) async throws -> [String] {
        // Upload each RAW file to object storage, return storage keys.
        throw ProcessingError.uploadFailed("Upload not implemented")
    }

    private func submitJob(assetKeys: [String]) async throws -> String {
        // POST /stack with asset keys, return job ID.
        throw ProcessingError.remoteJobFailed("Job submission not implemented")
    }

    private func pollJob(id: String) async throws -> String {
        // GET /status/{id} on an interval until state == "done" or timeout.
        let deadline = Date().addingTimeInterval(jobTimeoutSeconds)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
            // TODO: check job status and return result key when ready
        }
        throw ProcessingError.remoteJobFailed("Job timed out after \(Int(jobTimeoutSeconds))s")
    }

    private func downloadResult(key: String) async throws -> UIImage {
        // Download the stacked master from object storage and decode to UIImage.
        throw ProcessingError.remoteJobFailed("Result download not implemented")
    }
}
