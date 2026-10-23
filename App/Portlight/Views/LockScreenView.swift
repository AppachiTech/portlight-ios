import SwiftUI

struct LockScreenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.portlightNight.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                PortlightMark(size: 120)
                VStack(spacing: 8) {
                    Text("Portlight")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Locked")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                switch model.lock.status {
                case .unavailable(let reason):
                    Label(reason, systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Try again") { Task { await model.lock.unlock() } }
                        .buttonStyle(.bordered)
                        .tint(.white)
                case .unlocking:
                    ProgressView().tint(.white)
                default:
                    if let message = model.lock.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Button {
                        Task { await model.lock.unlock() }
                    } label: {
                        Label("Unlock with \(model.lock.biometryName)", systemImage: "lock.open")
                            .font(.headline)
                            .frame(maxWidth: 320)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.portlightBrass)
                    .foregroundStyle(Color.portlightNight)
                }
                Spacer().frame(height: 40)
            }
            .padding()
        }
    }
}

/// The app's mark: a brass portlight with a prompt inside.
struct PortlightMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.portlightBrass)
            Circle()
                .fill(Color.portlightGlass)
                .padding(size * 0.14)
            ForEach(0..<8) { index in
                Circle()
                    .fill(Color.portlightNight.opacity(0.55))
                    .frame(width: size * 0.06, height: size * 0.06)
                    .offset(y: -size * 0.43)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Text(">_")
                .font(.system(size: size * 0.3, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.portlightBrass)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
