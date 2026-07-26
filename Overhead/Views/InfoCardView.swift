import SwiftUI
import OverheadCore

struct InfoCardView: View {
    let snapshot: SatelliteSnapshot
    let observer: ObserverLocation?

    @State private var passes: [SatellitePass] = []
    @State private var passesLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                    .padding(24)

                separator

                liveSection
                    .padding(24)

                separator

                passSection
                    .padding(24)

                contextSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: snapshot.id) {
            await loadPasses()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.object.name)
                .font(.title3.bold())
            Text("NORAD \(snapshot.object.id) · \(categoryLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 6)
            Text("\(Int(snapshot.look.rangeKm)) km away · \(Int(snapshot.look.elevationDegrees))° above horizon")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Live

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Live")
            row("Altitude",  String(format: "%.0f km", snapshot.altitudeKm))
            row("Speed",     String(format: "%.2f km/s", snapshot.speedKmPerSec),
                             detail: String(format: "%@ km/h", Int(snapshot.speedKmPerSec * 3600).formatted()))
            row("Direction", "\(cardinal(snapshot.look.azimuthDegrees)) · \(Int(snapshot.look.azimuthDegrees))°")
        }
    }

    // MARK: - Pass

    private var passSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Pass")
            if !passesLoaded {
                Text("Computing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    passRows(at: ctx.date)
                }
            }
        }
    }

    @ViewBuilder
    private func passRows(at now: Date) -> some View {
        let current = passes.first { $0.riseTime <= now && $0.setTime >= now }
        let next    = passes.first { $0.riseTime > now }

        if let pass = current {
            let peaksIn = pass.maxElevationTime.timeIntervalSince(now)
            let setsIn  = pass.setTime.timeIntervalSince(now)
            if peaksIn > 0 {
                row("Peaks in", formatDuration(peaksIn),
                    detail: String(format: "%.0f° max", pass.maxElevationDegrees))
            }
            row("Sets in", formatDuration(max(0, setsIn)))
        } else if let pass = next {
            row("Next pass",     formatPassTime(pass.riseTime))
            row("Max elevation", String(format: "%.0f°", pass.maxElevationDegrees))
        } else {
            Text("No passes in the next 24 hours.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Context

    private var contextSection: some View {
        Text("Travelling \(Int(snapshot.speedKmPerSec * 3600).formatted()) km/h, circling Earth every \(Int(orbitalPeriodMinutes)) minutes.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Reusable components

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 1)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }

    private func row(_ label: String, _ value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .monospacedDigit()
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }

    // MARK: - Helpers

    private var categoryLabel: String {
        switch snapshot.object.category {
        case .stations: return "Space Station"
        case .starlink: return "SpaceX Starlink"
        }
    }

    private func cardinal(_ az: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int((az + 22.5) / 45) % 8]
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(max(0, t))
        let m = total / 60, s = total % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private func formatPassTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var orbitalPeriodMinutes: Double {
        let r = (6371.0 + snapshot.altitudeKm) * 1000.0
        return 2 * .pi * pow(r, 1.5) / sqrt(3.986004418e14) / 60
    }

    // MARK: - Pass loading

    private func loadPasses() async {
        guard let observer else { passesLoaded = true; return }
        let object = snapshot.object
        passes = await Task.detached(priority: .utility) {
            PassPredictor.nextPasses(
                for: object,
                observer: observer,
                from: Date(),
                searchWindow: 24 * 3600,
                stepSeconds: 30,
                maxPasses: 5
            )
        }.value
        passesLoaded = true
    }
}
