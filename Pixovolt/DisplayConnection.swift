import Foundation
import CoreGraphics
import Darwin

struct ConnectionIdentity: Codable, Equatable {
    let uuid: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
}

struct ConnectionDisplay: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let builtIn: Bool
    let active: Bool
    let online: Bool
    let physical: Bool
    var vendor: UInt32 = 0
    var model: UInt32 = 0
    var serial: UInt32 = 0
    var identity: ConnectionIdentity { ConnectionIdentity(uuid: uuid, vendor: vendor, model: model, serial: serial) }
}

enum ConnectionPolicy {
    static func target(uuid: String, in displays: [ConnectionDisplay], enabling: Bool, fallback: ConnectionIdentity? = nil) throws -> ConnectionDisplay {
        guard UUID(uuidString: uuid) != nil else { throw DDCError.message("유효하지 않은 모니터 UUID입니다.") }
        var matches = displays.filter { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame && $0.physical }
        if matches.isEmpty, enabling, let fallback, fallback.uuid.caseInsensitiveCompare(uuid) == .orderedSame,
           fallback.vendor != 0, fallback.model != 0, fallback.serial != 0 {
            matches = displays.filter { $0.physical && !$0.builtIn && $0.vendor == fallback.vendor && $0.model == fallback.model && $0.serial == fallback.serial }
        }
        guard matches.count == 1, let target = matches.first else {
            throw DDCError.message("대상 모니터를 찾거나 구분하지 못했습니다. 케이블을 다시 연결한 뒤 시도하세요.")
        }
        guard !target.builtIn else { throw DDCError.message("노트북 내장 화면은 연결 해제 대상이 아닙니다.") }
        if !enabling && target.online {
            guard displays.contains(where: { $0.builtIn && $0.active && $0.online && $0.id != target.id }) else {
                throw DDCError.message("노트북 내장 화면이 활성화돼 있어야 연결을 해제할 수 있습니다. 노트북 덮개를 열고 다시 시도하세요.")
            }
        }
        return target
    }
}

// Private API prototypes are dynamically resolved; missing symbols fail without mutating the display configuration.
// References: DisplayPlacer and MacDisplay; see Vendor/DisplayConnection-NOTES.md.
actor DisplayConnectionService {
    typealias ListFunction = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    typealias EnableFunction = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private let framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    private func functions() throws -> (ListFunction, EnableFunction) {
        guard let handle = framework,
              let list = dlsym(handle, "CGSGetDisplayList"),
              let enable = dlsym(handle, "CGSConfigureDisplayEnabled") else {
            throw DDCError.message("이 macOS에서 화면 연결 제어 API를 사용할 수 없습니다.")
        }
        // Keep the loaded framework alive for the lifetime of the process.
        return (unsafeBitCast(list, to: ListFunction.self), unsafeBitCast(enable, to: EnableFunction.self))
    }
    typealias InfoFunction = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
    private let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL)
    private func snapshot(_ list: ListFunction) throws -> [ConnectionDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 128)
        var count: UInt32 = 0
        guard list(128, &ids, &count) == .success, count <= 128 else {
            throw DDCError.message("시스템의 화면 목록을 읽지 못했습니다.")
        }
        guard let coreDisplay, let symbol = dlsym(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary") else {
            throw DDCError.message("모니터 UUID를 확인할 수 없어 화면 연결 변경을 중지했습니다.")
        }
        let info = unsafeBitCast(symbol, to: InfoFunction.self)
        return ids.prefix(Int(count)).map { id in
            let dictionary = info(id)?.takeRetainedValue() as NSDictionary?
            let uuidText = dictionary?["kCGDisplayUUID"] as? String ?? ""
            let physical = CGDisplayIsBuiltin(id) != 0 || CGDisplayVendorNumber(id) != 0 || CGDisplayModelNumber(id) != 0
            return ConnectionDisplay(id: id, uuid: uuidText, builtIn: CGDisplayIsBuiltin(id) != 0,
                                     active: CGDisplayIsActive(id) != 0, online: CGDisplayIsOnline(id) != 0, physical: physical, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
        }
    }
    func availableDisplays() throws -> [ConnectionDisplay] {
        let (list, _) = try functions()
        return try snapshot(list)
    }
    func identity(uuid: String) throws -> ConnectionIdentity {
        let (list, _) = try functions()
        return try ConnectionPolicy.target(uuid: uuid, in: snapshot(list), enabling: true).identity
    }
    func setEnabled(uuid: String, enabled: Bool, fallback: ConnectionIdentity? = nil) throws {
        let (list, configure) = try functions()
        // Resolve the UUID against fresh private enumeration immediately before every transaction.
        let target = try ConnectionPolicy.target(uuid: uuid, in: snapshot(list), enabling: enabled, fallback: fallback)
        if target.online == enabled { return }
        var configuration: CGDisplayConfigRef?
        let started = CGBeginDisplayConfiguration(&configuration)
        guard started == .success, let configuration else {
            throw DDCError.message("화면 설정을 시작하지 못했습니다 (\(started.rawValue)).")
        }
        if CGDisplayIsInMirrorSet(target.id) != 0 {
            CGCancelDisplayConfiguration(configuration)
            throw DDCError.message("미러링 중인 화면은 지원하지 않습니다. 시스템 디스플레이 설정에서 확장 모드로 바꿔주세요.")
        }
        let changed = configure(configuration, target.id, enabled)
        guard changed == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw DDCError.message("화면 연결 변경 실패 (\(changed.rawValue)). 케이블을 다시 연결하면 복구할 수 있습니다.")
        }
        let committed = CGCompleteDisplayConfiguration(configuration, .forSession)
        guard committed == .success else {
            throw DDCError.message("화면 설정 적용 실패 (\(committed.rawValue)). 케이블을 다시 연결한 뒤 시도하세요.")
        }
        // Poll read-only state; never issue repeated disable commands.
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.2)
            let displays = try snapshot(list)
            if let current = try? ConnectionPolicy.target(uuid: uuid, in: displays, enabling: true, fallback: fallback ?? target.identity), current.online == enabled { return }
        }
        throw DDCError.message("요청 후 화면 연결 상태를 확인하지 못했습니다. ‘다시 연결’을 시도하거나 케이블을 분리 후 연결하세요.")
    }
}
