import Testing
@testable import Screenie

@Suite("Screenshot processing source")
struct ScreenshotProcessingSourceTests {
    @Test("Only watched files require Apple selection metadata")
    func metadataPolicy() {
        #expect(ScreenshotProcessingSource.watchedSelection.requiresSelectionMetadata)
        #expect(!ScreenshotProcessingSource.shortcut.requiresSelectionMetadata)
        #expect(!ScreenshotProcessingSource.manual.requiresSelectionMetadata)
    }

    @Test("Watched and shortcut uploads share the safety quota")
    func quotaPolicy() {
        #expect(ScreenshotProcessingSource.watchedSelection.consumesRequestQuota)
        #expect(ScreenshotProcessingSource.shortcut.consumesRequestQuota)
        #expect(!ScreenshotProcessingSource.manual.consumesRequestQuota)
    }
}
