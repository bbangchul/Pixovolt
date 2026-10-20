import Carbon
import Foundation

final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onPress: ((Int) -> Void)?
    static let signature: OSType = 0x4D535743
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            owner.onPress?(Int(id.id) - 1)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func clear() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }
    func register(modifiers: UInt32, keyCodes: [UInt32]) throws {
        clear()
        guard handler != nil else { throw DDCError.message("전역 단축키 이벤트를 등록하지 못했습니다.") }
        guard Set(keyCodes).count == keyCodes.count else { throw DDCError.message("각 입력에 서로 다른 숫자 키를 지정하세요.") }
        for (index, code) in keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                clear()
                throw DDCError.message("단축키가 다른 앱과 충돌하거나 등록되지 않았습니다 (\(status)). 조합을 변경하세요.")
            }
            refs.append(ref)
        }
    }
    deinit { clear(); if let handler { RemoveEventHandler(handler) } }
}
