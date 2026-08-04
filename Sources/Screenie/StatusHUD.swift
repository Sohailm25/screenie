import AppKit

@MainActor
final class StatusHUD {
    private let panel: NSPanel
    private let iconView: NSImageView
    private let label: NSTextField
    private var hideTimer: Timer?

    init() {
        let frame = NSRect(x: 0, y: 0, width: 330, height: 58)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true

        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        iconView = NSImageView(frame: NSRect(x: 18, y: 17, width: 24, height: 24))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        effect.addSubview(iconView)

        label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 54, y: 12, width: 258, height: 34)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        effect.addSubview(label)

        panel.contentView = effect
    }

    func showProgress(_ message: String) {
        show(message, symbol: "ellipsis.circle", autoHideAfter: nil)
    }

    func showSuccess(_ message: String) {
        show(message, symbol: "checkmark.circle.fill", autoHideAfter: 1.4)
    }

    func showError(_ message: String) {
        show(message, symbol: "exclamationmark.triangle.fill", autoHideAfter: 3.5)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
    }

    private func show(_ message: String, symbol: String, autoHideAfter delay: TimeInterval?) {
        hideTimer?.invalidate()
        label.stringValue = message
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        positionPanel()
        panel.orderFrontRegardless()

        if let delay {
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.panel.orderOut(nil)
                }
            }
        }
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let frame = panel.frame
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.maxY - frame.height - 28
        )
        panel.setFrameOrigin(origin)
    }
}
