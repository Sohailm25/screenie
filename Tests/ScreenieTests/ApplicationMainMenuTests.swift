import AppKit
import Testing
@testable import Screenie

@Suite("Application main menu")
struct ApplicationMainMenuTests {
    @Test("Command-V routes Paste through the responder chain")
    @MainActor
    func installsPasteCommand() throws {
        let mainMenu = ApplicationMainMenu.make()
        let editMenu = try #require(
            mainMenu.items.compactMap(\.submenu).first { $0.title == "Edit" }
        )
        let pasteItem = try #require(
            editMenu.items.first { $0.action == NSSelectorFromString("paste:") }
        )

        #expect(pasteItem.keyEquivalent == "v")
        #expect(pasteItem.keyEquivalentModifierMask == .command)
        #expect(pasteItem.target == nil)
    }
}
