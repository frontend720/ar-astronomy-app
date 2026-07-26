import SwiftUI

struct GalleryView: View {
    @State private var imageURLs: [URL] = []
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if imageURLs.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "photo.stack")
                            .font(.system(size: 52))
                            .foregroundStyle(.secondary)
                        Text("No stacked images yet")
                            .font(.headline)
                        Text("Use the capture tool to stack and save your astro frames.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(imageURLs, id: \.self) { url in
                                GalleryThumbnailView(url: url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Astro Gallery")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { reload() }
    }

    private func reload() {
        let dir = AstrophotographyEngine.galleryDirectory
        imageURLs = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ))?.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aDate > bDate
        } ?? []
    }
}

private struct GalleryThumbnailView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.1)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task { image = await loadThumbnail() }
    }

    private func loadThumbnail() async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }
}
