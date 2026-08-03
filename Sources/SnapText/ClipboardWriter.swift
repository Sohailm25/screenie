import AppKit

enum ClipboardCommitPolicy {
    static func shouldWrite(startingChangeCount: Int, currentChangeCount: Int) -> Bool {
        startingChangeCount == currentChangeCount
    }
}

@MainActor
enum ClipboardWriter {
    @discardableResult
    static func write(_ text: String, pasteboard: NSPasteboard = .general) -> Bool {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
