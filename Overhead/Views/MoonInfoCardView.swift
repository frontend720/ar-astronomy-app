import SwiftUI
import OverheadCore

struct MoonInfoCardView: View {
    let snapshot: MoonSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Moon")
                    .font(.title2.bold())
                Text(snapshot.phaseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    statTile(title: "Distance", value: String(format: "%.0f km", snapshot.distanceKm))
                    statTile(title: "Illumination", value: String(format: "%.0f%%", snapshot.illuminationFraction * 100))
                }
                GridRow {
                    statTile(title: "Azimuth", value: String(format: "%.0f°", snapshot.azimuthDegrees))
                    statTile(title: "Elevation", value: String(format: "%.0f°", snapshot.elevationDegrees))
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
        }
    }
}
