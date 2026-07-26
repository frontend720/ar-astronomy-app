import SwiftUI

struct SettingsView: View {
    @Binding var maxVisibleStarlink: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Settings")
                .font(.title2.bold())
                .padding(.bottom, 4)

            settingsSection("Starlink") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Max visible satellites")
                        Text("Nearest above the horizon are shown first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Stepper("\(maxVisibleStarlink)", value: $maxVisibleStarlink, in: 1...25)
                        .fixedSize()
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .tracking(1)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
