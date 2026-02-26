import SwiftUI

/// Shown while waiting for biometric / passcode authentication.
struct LockView: View {
    @ObservedObject var biometric: BiometricGuard

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("openme")
                .font(.largeTitle.bold())

            if let err = biometric.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Unlock") {
                Task { await biometric.authenticate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
