//
//  openme_macosTests.swift
//  openme-macosTests
//

import Testing
@testable import openme_macos

/// Unit tests for the openme macOS application.
///
/// These tests cover app-level behaviour that is not already tested by the
/// OpenMeKit SPM package tests (see apple/OpenMeKit/Tests/).

// MARK: - KnockIntent smoke tests

@Test("KnockIntent does not open app when run")
func knockIntentDoesNotOpenApp() {
    // The intent should silently deliver the knock without bringing the app foregrounded.
    #expect(KnockIntent.openAppWhenRun == false)
}

@Test("StartContinuousKnockIntent does not open app when run")
func continuousKnockIntentDoesNotOpenApp() {
    #expect(StartContinuousKnockIntent.openAppWhenRun == false)
}

@Test("StopContinuousKnockIntent does not open app when run")
func stopContinuousKnockIntentDoesNotOpenApp() {
    #expect(StopContinuousKnockIntent.openAppWhenRun == false)
}

