import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey via Carbon's `RegisterEventHotKey`. Works for a background
/// (`.accessory`) app and needs no Accessibility permission, unlike a global
/// `NSEvent` monitor. Modifiers use Carbon masks (`cmdKey`, `optionKey`, …).
@MainActor
final class HotKey {
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, selfPtr, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x424F4953), id: 1) // 'BOIS'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    fileprivate func fire() { action() }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

/// C trampoline. Carbon dispatches hotkey events on the main thread.
private func hotKeyHandler(_ callRef: EventHandlerCallRef?,
                           _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotKey.fire() }
    return noErr
}
