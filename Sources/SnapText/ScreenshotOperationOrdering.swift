import Foundation

enum ScreenshotOperationOrdering {
    static func watchedCaptureShouldSupersedeShortcut(
        discoverySequence: UInt64,
        shortcutBoundary: UInt64?
    ) -> Bool {
        guard let shortcutBoundary else { return true }
        return discoverySequence > shortcutBoundary
    }
}
