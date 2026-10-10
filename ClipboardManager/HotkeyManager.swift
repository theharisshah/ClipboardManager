import Carbon
import Foundation

/// Registers the global ⇧⌘V hotkey and calls `showHideCallback` on the main queue when it is pressed.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotkeyID = EventHotKeyID(signature: OSType(0x43424D52), id: 1) // 'CBMR'
    private let showHideCallback: () -> Void

    /// False when the shortcut couldn't be registered, for example because another app already uses it.
    private(set) var isRegistered = false

    init(showHideCallback: @escaping () -> Void) {
        self.showHideCallback = showHideCallback
        registerHotkey()
    }

    deinit {
        unregisterHotkey()
    }

    private func registerHotkey() {
        // Register Cmd+Shift+V hotkey
        let keyCode = UInt32(kVK_ANSI_V)
        let modifierFlags = UInt32(cmdKey | shiftKey)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        // The handler gets an unretained pointer to self, so it must be removed in deinit (see unregisterHotkey).
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, theEvent, userData -> OSStatus in
            guard let theEvent = theEvent, let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hkCom = EventHotKeyID()
            let err = GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkCom)

            // Leave other hotkey events to other handlers.
            guard err == noErr, hkCom.signature == manager.hotkeyID.signature, hkCom.id == manager.hotkeyID.id else {
                return OSStatus(eventNotHandledErr)
            }

            DispatchQueue.main.async {
                manager.showHideCallback()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)

        guard handlerStatus == noErr else {
            NSLog("ClipboardManager: couldn't install the hotkey handler (OSStatus %d)", handlerStatus)
            return
        }

        let status = RegisterEventHotKey(keyCode, modifierFlags, hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
        if !isRegistered {
            NSLog("ClipboardManager: couldn't register ⇧⌘V (OSStatus %d)", status)
        }
    }

    private func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        isRegistered = false
    }
}
