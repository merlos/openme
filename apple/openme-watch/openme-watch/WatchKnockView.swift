import OpenMeKit
import SwiftUI

/// Watch detail view: knock now or toggle continuous knocking.
struct WatchKnockView: View {
    let profileName: String
    @EnvironmentObject var knockManager: KnockManager

    @State private var status: KnockStatus = .idle

    enum KnockStatus {
        case idle, sending, success, failure(String)

        var label: String {
            switch self {
            case .idle:         return "Knock"
            case .sending:      return "Sending…"
            case .success:      return "✓ Sent"
            case .failure:      return "✗ Failed"
            }
        }

        var color: Color {
            switch self {
            case .idle, .sending: return .accentColor
            case .success:        return .green
            case .failure:        return .red
            }
        }
    }

    private var isContinuous: Bool {
        knockManager.continuousKnockProfile == profileName
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isContinuous ? "waveform" : "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(isContinuous ? .green : .accentColor)
                .symbolEffect(.bounce, value: status)

            Text(profileName)
                .font(.headline)
                .lineLimit(1)

            // Knock now button
            Button {
                sendKnock()
            } label: {
                Text(status.label)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(status.color)
            .disabled(status == .sending)

            // Continuous toggle
            Button {
                if isContinuous {
                    knockManager.stopContinuousKnock()
                } else {
                    knockManager.startContinuousKnock(profile: profileName)
                }
            } label: {
                Label(isContinuous ? "Stop auto" : "Start auto",
                      systemImage: isContinuous ? "stop.fill" : "repeat")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isContinuous ? .red : .secondary)
        }
        .navigationTitle(profileName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendKnock() {
        status = .sending
        knockManager.knock(profile: profileName) { result in
            switch result {
            case .success:
                status = .success
                WKInterfaceDevice.current().play(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { status = .idle }
            case .failure(let e):
                status = .failure(e)
                WKInterfaceDevice.current().play(.failure)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { status = .idle }
            }
        }
    }
}
