import Carbon.HIToolbox
import Testing
@testable import Screenie

@Suite("Global capture shortcut")
struct GlobalHotKeyTests {
    @Test("Capture shortcut is Command-Option-4 and does not claim Apple's shortcut")
    @MainActor
    func usesDedicatedShortcut() {
        #expect(GlobalHotKeyController.keyCode == UInt32(kVK_ANSI_4))
        #expect(GlobalHotKeyController.modifiers == UInt32(cmdKey | optionKey))
        #expect(GlobalHotKeyController.modifiers & UInt32(shiftKey) == 0)
        #expect(GlobalHotKeyController.displayName == "⌘⌥4")
    }

    @Test("Enabled matching system shortcuts are rejected")
    @MainActor
    func detectsSystemConflict() {
        let matching = SymbolicHotKeyDescriptor(
            keyCode: GlobalHotKeyController.keyCode,
            modifiers: GlobalHotKeyController.modifiers,
            isEnabled: true
        )
        let disabled = SymbolicHotKeyDescriptor(
            keyCode: GlobalHotKeyController.keyCode,
            modifiers: GlobalHotKeyController.modifiers,
            isEnabled: false
        )

        #expect(GlobalHotKeyController.containsShortcutConflict(in: [matching]))
        #expect(!GlobalHotKeyController.containsShortcutConflict(in: [disabled]))
    }
}
