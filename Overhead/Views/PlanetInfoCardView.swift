import SwiftUI
import OverheadCore

struct PlanetInfoCardView: View {
    let snapshot: PlanetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.name)
                    .font(.title2.bold())
                Text("Planet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    statTile(title: "Distance", value: distanceString)
                    statTile(title: "Magnitude", value: magnitudeString)
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

    private var distanceString: String {
        let au = snapshot.distanceAU
        let mkm = au * 149.598
        if mkm >= 1000 {
            return String(format: "%.2f AU", au)
        }
        return String(format: "%.0f M km", mkm)
    }

    private var magnitudeString: String {
        let m = snapshot.magnitude
        return m >= 0 ? String(format: "+%.1f", m) : String(format: "%.1f", m)
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
