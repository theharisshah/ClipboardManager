import Foundation
import Carbon
import SwiftUI

class HotkeyManager: ObservableObject {
    private var hotKeyRef: EventHotKeyRef?
    private let hotkeyID = EventHotKeyID(signature: OSType(0x43424D52), id: 1) // 'CBMR'
    private let showHideCallback: () -> Void
    
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
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hkCom = EventHotKeyID()
            let err = GetEventParameter(theEvent, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkCom)
            
            if err == noErr && hkCom.signature == manager.hotkeyID.signature && hkCom.id == manager.hotkeyID.id {
                DispatchQueue.main.async {
                    manager.showHideCallback()
                }
            }
            
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        
        RegisterEventHotKey(keyCode, modifierFlags, hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    private func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
} 