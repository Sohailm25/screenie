import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case handlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
    case systemShortcutConflict

    var errorDescription: String? {
        switch self {
        case let .handlerInstallationFailed(status):
            return "SnapText could not install its keyboard shortcut handler (macOS error \(status))."
        case let .registrationFailed(status) where status == eventHotKeyExistsErr:
            return "Command-Option-4 is already reserved by another app. Use the SnapText menu or quit the conflicting app."
        case let .registrationFailed(status):
            return "SnapText could not register Command-Option-4 (macOS error \(status))."
        case .systemShortcutConflict:
            return "Command-Option-4 is assigned to a macOS system shortcut. Change that shortcut in System Settings or use the SnapText menu."
        }
    }
}

struct SymbolicHotKeyDescriptor: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let isEnabled: Bool
}

@MainActor
final class GlobalHotKeyController {
    static let displayName = "⌘⌥4"
    static let keyCode = UInt32(kVK_ANSI_4)
    static let modifiers = UInt32(cmdKey | optionKey)

    fileprivate static let identifier = EventHotKeyID(
        signature: OSType(0x536E_5478), // SnTx
        id: 1
    )

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private var keyIsDown = false

    var isRegistered: Bool {
        hotKeyReference != nil
    }

    func register(action: @escaping @MainActor () -> Void) throws {
        unregister()
        if Self.containsShortcutConflict(in: Self.systemSymbolicHotKeys()) {
            throw GlobalHotKeyError.systemShortcutConflict
        }
        self.action = action

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            snapTextHotKeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )
        guard handlerStatus == noErr, let installedHandler else {
            self.action = nil
            throw GlobalHotKeyError.handlerInstallationFailed(handlerStatus)
        }
        eventHandlerReference = installedHandler

        var registeredHotKey: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            Self.identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &registeredHotKey
        )
        guard registrationStatus == noErr, let registeredHotKey else {
            RemoveEventHandler(installedHandler)
            eventHandlerReference = nil
            self.action = nil
            throw GlobalHotKeyError.registrationFailed(registrationStatus)
        }
        hotKeyReference = registeredHotKey
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
        hotKeyReference = nil
        eventHandlerReference = nil
        action = nil
        keyIsDown = false
    }

    fileprivate func receive(eventKind: UInt32, identifier: EventHotKeyID) {
        guard
            identifier.signature == Self.identifier.signature,
            identifier.id == Self.identifier.id
        else { return }
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            guard !keyIsDown else { return }
            keyIsDown = true
            action?()
        case UInt32(kEventHotKeyReleased):
            keyIsDown = false
        default:
            break
        }
    }

    static func containsShortcutConflict(
        in descriptors: [SymbolicHotKeyDescriptor]
    ) -> Bool {
        descriptors.contains {
            $0.isEnabled
                && $0.keyCode == keyCode
                && $0.modifiers == modifiers
        }
    }

    private static func systemSymbolicHotKeys() -> [SymbolicHotKeyDescriptor] {
        var unmanagedHotKeys: Unmanaged<CFArray>?
        guard
            CopySymbolicHotKeys(&unmanagedHotKeys) == noErr,
            let hotKeys = unmanagedHotKeys?.takeRetainedValue() as NSArray?
        else { return [] }

        return hotKeys.compactMap { value in
            guard let dictionary = value as? NSDictionary else { return nil }
            let keyCode = (dictionary[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value
            let modifiers = (dictionary[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value
            let isEnabled = dictionary[kHISymbolicHotKeyEnabled] as? Bool
            guard let keyCode, let modifiers, let isEnabled else { return nil }
            return SymbolicHotKeyDescriptor(
                keyCode: keyCode,
                modifiers: modifiers,
                isEnabled: isEnabled
            )
        }
    }
}

private let snapTextHotKeyEventHandler: EventHandlerUPP = {
    _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard parameterStatus == noErr else { return parameterStatus }
    guard
        identifier.signature == OSType(0x536E_5478),
        identifier.id == 1
    else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let eventKind = GetEventKind(event)
    let capturedIdentifier = identifier
    DispatchQueue.main.async {
        controller.receive(eventKind: eventKind, identifier: capturedIdentifier)
    }
    return noErr
}
