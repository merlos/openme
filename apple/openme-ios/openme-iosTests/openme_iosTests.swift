import XCTest
@testable import openme_ios

/// Unit tests for the openme iOS application.
///
/// These tests cover app-level behaviour that is not already tested by the
/// OpenMeKit SPM package tests (see apple/OpenMeKit/Tests/).
final class openme_iosTests: XCTestCase {

    // MARK: - BiometricGuard

    @MainActor
    func testBiometricGuardStartsLocked() {
        let guard_ = BiometricGuard()
        XCTAssertFalse(guard_.isUnlocked,
                       "BiometricGuard must start in the locked state")
    }

    @MainActor
    func testBiometricGuardLockTransition() async {
        let guard_ = BiometricGuard()
        // In CI / simulator there are no biometrics — authenticate() sets
        // isUnlocked = true automatically (no biometrics → allow through).
        await guard_.authenticate()
        XCTAssertTrue(guard_.isUnlocked,
                      "BiometricGuard should auto-unlock when biometrics are unavailable")
        guard_.lock()
        XCTAssertFalse(guard_.isUnlocked, "lock() must transition back to locked state")
    }

    @MainActor
    func testBiometricGuardInitialError() {
        let guard_ = BiometricGuard()
        XCTAssertNil(guard_.error,
                     "BiometricGuard should have no error before authentication is attempted")
    }
}
