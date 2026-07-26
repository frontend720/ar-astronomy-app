import SwiftUI
import OverheadCore

struct DebugView: View {
    @ObservedObject var trackingService: SatelliteTrackingService
    let observer: ObserverLocation?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Debug")
                    .font(.title2.bold())
                    .padding(.bottom, 4)

                debugSection("TLE Catalog") {
                    row("Last fetch", ago(trackingService.lastCatalogSuccess))
                    row("Catalog size", trackingService.catalogObjectCount > 0
                        ? "\(trackingService.catalogObjectCount) objects"
                        : "Not loaded")
                    row("Visible now", "\(trackingService.snapshots.count) satellites")
                    row("Failures", "\(trackingService.consecutiveCatalogFailures)")
                }

                debugSection("Last Error") {
                    if let error = trackingService.lastError {
                        Text(error.localizedDescription)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        row("Status", "None")
                    }
                }

                debugSection("Bundled Files") {
                    // constellations.json lives in the OverheadCore package bundle,
                    // not Bundle.main — checked via ConstellationLines.project(observer:)
                    // returning non-empty, but we verify the resource URL directly here.
                    let found = ConstellationLines.bundleURL != nil
                    HStack {
                        Text("constellations.json")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label(found ? "Found" : "Missing", systemImage: found ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(found ? Color(red: 0.3, green: 0.9, blue: 0.5) : Color(red: 1, green: 0.45, blue: 0.45))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                debugSection("Location") {
                    if let obs = observer {
                        row("Latitude",  String(format: "%.5f°", obs.latitudeDegrees))
                        row("Longitude", String(format: "%.5f°", obs.longitudeDegrees))
                        row("Altitude",  String(format: "%.0f m", obs.altitudeMeters))
                    } else {
                        row("Status", "Waiting for GPS")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func debugSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .tracking(1)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func ago(_ date: Date) -> String {
        guard date != .distantPast else { return "Never" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
