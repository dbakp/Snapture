import AppKit
import Carbon.HIToolbox

/// Registers any number of global hotkeys via Carbon. One shared event handler
/// dispatches to per-hotkey callbacks by EventHotKeyID.id.
@MainActor
final class HotKeyManager {
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?
    private nonisolated(unsafe) var hotKeyRefs: [EventHotKeyRef] = []
    private var callbacks: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x534E4150 // 'SNAP'

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            var receivedID = EventHotKeyID()
            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &receivedID
            )
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = receivedID.id
            Task { @MainActor in
                manager.callbacks[id]?()
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
    }

    deinit {
        if let h = handlerRef { RemoveEventHandler(h) }
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
    }

    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        callbacks[id] = action

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers(from: modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr || ref == nil {
            // Another app owns this combo; capture stays reachable from the menu bar.
            NSLog("Snapture: hotkey registration failed for keyCode \(keyCode) (status \(status))")
            return
        }
        if let ref { hotKeyRefs.append(ref) }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command)  { result |= UInt32(cmdKey) }
        if flags.contains(.option)   { result |= UInt32(optionKey) }
        if flags.contains(.control)  { result |= UInt32(controlKey) }
        if flags.contains(.shift)    { result |= UInt32(shiftKey) }
        return result
    }
}
