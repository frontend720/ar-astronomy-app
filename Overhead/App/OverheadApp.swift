import SwiftUI
import OverheadCore

@main
struct OverheadApp: App {
    init() {
        // After deploying backend/worker.js, replace nil with your worker URL:
        // CelestrakClient.proxyBaseURL = URL(string: "https://overhead-tle-proxy.YOUR-SUBDOMAIN.workers.dev")!
        CelestrakClient.proxyBaseURL = nil
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
