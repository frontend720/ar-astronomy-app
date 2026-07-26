import SwiftUI

struct CompassCalibrationOverlay: View {
    let onDismiss: () -> Void

    @State private var isVisible = false

    private static let cycleDuration: TimeInterval = 3.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Calibrate your compass")
                    .font(.headline)
                    .foregroundStyle(.white)

                figure8View
                    .frame(width: 200, height: 120)

                VStack(spacing: 6) {
                    Text("Slowly trace a figure-8 with your phone")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("This aligns the AR sky view with the real sky.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }

                Button("Got it", action: beginDismiss)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(40)
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { isVisible = true }
            Task {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                beginDismiss()
            }
        }
    }

    private var figure8View: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.cycleDuration) / Self.cycleDuration * 2 * .pi
            Canvas { ctx, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let rx = size.width * 0.40
                let ry = size.height * 0.38

                // Dashed guide path
                var guide = Path()
                for i in 0...120 {
                    let a = Double(i) / 120.0 * 2 * .pi
                    let px = cx + sin(a) * rx
                    let py = cy + sin(2 * a) / 2 * ry
                    if i == 0 { guide.move(to: CGPoint(x: px, y: py)) }
                    else { guide.addLine(to: CGPoint(x: px, y: py)) }
                }
                guide.closeSubpath()
                ctx.stroke(guide, with: .color(.white.opacity(0.2)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))

                // Motion trail
                for i in stride(from: 6, through: 1, by: -1) {
                    let tt = t - Double(i) * 0.12
                    let tx = cx + sin(tt) * rx
                    let ty = cy + sin(2 * tt) / 2 * ry
                    let r = max(0.0, 5.0 - Double(i) * 0.6)
                    let alpha = max(0.0, 0.5 - Double(i) * 0.07)
                    ctx.fill(Path(ellipseIn: CGRect(x: tx - r, y: ty - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
                }

                // Leading dot
                let hx = cx + sin(t) * rx
                let hy = cy + sin(2 * t) / 2 * ry
                ctx.fill(Path(ellipseIn: CGRect(x: hx - 7, y: hy - 7, width: 14, height: 14)),
                         with: .color(.white))
            }
        }
    }

    private func beginDismiss() {
        withAnimation(.easeOut(duration: 0.4)) { isVisible = false }
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            onDismiss()
        }
    }
}
