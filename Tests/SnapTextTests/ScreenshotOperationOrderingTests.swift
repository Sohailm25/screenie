import Foundation
import Testing
@testable import SnapText

@Suite("Screenshot operation ordering")
struct ScreenshotOperationOrderingTests {
    @Test("A delayed older watcher callback cannot cancel a newer shortcut")
    func rejectsOlderWatcherCallback() {
        let shortcutBoundary: UInt64 = 20

        #expect(
            !ScreenshotOperationOrdering.watchedCaptureShouldSupersedeShortcut(
                discoverySequence: 20,
                shortcutBoundary: shortcutBoundary
            )
        )
        #expect(
            ScreenshotOperationOrdering.watchedCaptureShouldSupersedeShortcut(
                discoverySequence: 21,
                shortcutBoundary: shortcutBoundary
            )
        )
    }

    @Test("A newly discovered screenshot is newer even if its file timestamp is old")
    func ignoresFileTimestampForOrdering() {
        #expect(
            ScreenshotOperationOrdering.watchedCaptureShouldSupersedeShortcut(
                discoverySequence: 8,
                shortcutBoundary: 7
            )
        )
    }
}
