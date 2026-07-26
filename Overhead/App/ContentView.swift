import SwiftUI
import UIKit
import OverheadCore

struct ContentView: View {
    @StateObject private var locationService = LocationService()
    @StateObject private var trackingService = SatelliteTrackingService()
    @State private var selectedSnapshot: SatelliteSnapshot?
    @State private var selectedPlanet: PlanetSnapshot?
    @State private var selectedMoon: MoonSnapshot?
    @State private var showingDebug = false
    @State private var showingSettings = false
    @State private var showingCapture = false
    @State private var trackingStarted = false
    @State private var showCalibrationOverlay = false

    @AppStorage("maxVisibleStarlink") private var maxVisibleStarlink: Int = 10
    @AppStorage("skyLayer") private var skyLayer: SkyLayer = .all

    var body: some View {
        ZStack {
            switch locationService.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                SkyARView(snapshots: trackingService.snapshots, observer: locationService.observerLocation, selectedID: selectedSnapshot?.id, layer: skyLayer, onSelect: { selectedSnapshot = $0 }, onSelectPlanet: { selectedPlanet = $0 }, onSelectMoon: { selectedMoon = $0 })
                    .ignoresSafeArea()

                if trackingService.snapshots.isEmpty, let error = trackingService.lastError {
                    VStack {
                        Text(Self.summarize(error))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 56)
                        Spacer()
                    }
                }

            case .denied, .restricted:
                PermissionDeniedView()
            default:
                PermissionPromptView(action: locationService.requestAuthorization)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Button { skyLayer = skyLayer.next } label: {
                Image(systemName: skyLayer.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.bottom, 32)
            .padding(.leading, 16)
        }
        .overlay(alignment: .topLeading) {
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 52)
            .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Button { showingDebug = true } label: {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Button { showingCapture = true } label: {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.top, 52)
            .padding(.trailing, 16)
        }
        .task(id: locationService.observerLocation?.latitudeDegrees) {
            guard let observer = locationService.observerLocation, !trackingStarted else { return }
            trackingStarted = true
            showCalibrationOverlay = true
            trackingService.maxVisibleStarlink = maxVisibleStarlink
            await trackingService.start(observer: observer)
        }
        .onChange(of: maxVisibleStarlink) { newValue in
            trackingService.maxVisibleStarlink = newValue
        }
        .sheet(item: $selectedSnapshot) { snapshot in
            InfoCardView(snapshot: snapshot, observer: locationService.observerLocation)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedPlanet) { planet in
            PlanetInfoCardView(snapshot: planet)
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedMoon) { moon in
            MoonInfoCardView(snapshot: moon)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(maxVisibleStarlink: $maxVisibleStarlink)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingDebug) {
            DebugView(trackingService: trackingService, observer: locationService.observerLocation)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingCapture) {
            CaptureView()
        }
        .overlay {
            if showCalibrationOverlay {
                CompassCalibrationOverlay { showCalibrationOverlay = false }
            }
        }
        .onAppear { locationService.requestAuthorization() }
    }

    private static func summarize(_ error: Error) -> String {
        guard let celestrakError = error as? CelestrakError else {
            return "Satellite data unavailable right now — will retry automatically."
        }
        switch celestrakError {
        case .httpError(let status, _):
            return "Satellite data unavailable (server returned \(status)) — will retry automatically."
        case .invalidResponse, .emptyCatalog:
            return "Satellite data unavailable right now — will retry automatically."
        }
    }
}

struct PermissionPromptView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.circle")
                .font(.system(size: 48))
            Text("Overhead needs your location")
                .font(.headline)
            Text("Your position aligns the AR view with the real positions of the ISS and other satellites overhead.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Enable Location", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
            Text("Location access is off")
                .font(.headline)
            Text("Enable location for Overhead in Settings to see satellites aligned with the real sky.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
