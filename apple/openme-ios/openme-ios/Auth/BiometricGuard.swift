import Combine
import LocalAuthentication
import SwiftUI

/// Manages Face ID / Touch ID at app launch.
@MainActor
final class BiometricGuard: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var error: String?

    private let context = LAContext()

    func authenticate() async {
        // Skip if biometrics are unavailable (simulator, no hardware).
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            isUnlocked = true   // No biometrics → allow through
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to access openme"
            )
            isUnlocked = success
        } catch {
            self.error = error.localizedDescription
            // Fall back to device passcode path — already handled by .deviceOwnerAuthentication.
        }
    }

    func lock() { isUnlocked = false }
}
