import SwiftUI
import PhotosUI

struct CaptureView: View {
    @StateObject private var engine = AstrophotographyEngine()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoadingImages = false
    @State private var savedURL: URL?
    @State private var saveError: Error?
    @State private var showingGallery = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // Tier badge
                    Label(engine.tierDescription,
                          systemImage: engine.strategy.tier == .local ? "cpu" : "cloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    // Frame picker
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 25,
                        matching: .images
                    ) {
                        Label(
                            selectedItems.isEmpty
                                ? "Select Frames"
                                : "\(selectedItems.count) frame\(selectedItems.count == 1 ? "" : "s") selected",
                            systemImage: "photo.stack"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .onChange(of: selectedItems) { _ in
                        savedURL = nil
                        saveError = nil
                    }

                    // Stack button
                    Button {
                        Task { await loadAndProcess() }
                    } label: {
                        Label("Stack Images", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedItems.isEmpty || engine.isProcessing || isLoadingImages)

                    // Progress
                    if isLoadingImages || engine.isProcessing {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(isLoadingImages ? "Loading frames…" : "Stacking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Result
                    if let image = engine.result {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)

                        if savedURL != nil {
                            Label("Saved to gallery", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                do {
                                    savedURL = try engine.saveResult()
                                } catch {
                                    saveError = error
                                }
                            } label: {
                                Label("Save to Gallery", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    // Errors
                    if let error = engine.lastError ?? saveError {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Astrophotography")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingGallery = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                }
            }
            .sheet(isPresented: $showingGallery) {
                GalleryView()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadAndProcess() async {
        isLoadingImages = true
        savedURL = nil
        saveError = nil
        var tempURLs: [URL] = []

        for item in selectedItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try? data.write(to: url)
            tempURLs.append(url)
        }

        isLoadingImages = false
        await engine.processStack(images: tempURLs)

        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
