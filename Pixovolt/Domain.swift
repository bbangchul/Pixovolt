import Foundation

struct EDIDIdentity: Equatable {
    let manufacturerCode: String
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32?
    let modelName: String?
    static func parse(_ data: Data) -> EDIDIdentity? {
        let bytes = Array(data)
        guard bytes.count >= 128, Array(bytes.prefix(8)) == [0,255,255,255,255,255,255,0],
              bytes.prefix(128).reduce(0, { ($0 + Int($1)) & 255 }) == 0 else { return nil }
        let vendor = UInt32(bytes[8]) << 8 | UInt32(bytes[9])
        let characters = [10,5,0].map { Int((vendor >> $0) & 31) }
        guard characters.allSatisfy({ (1...26).contains($0) }) else { return nil }
        let maker = String(characters.map { Character(UnicodeScalar($0 + 64)!) })
        let product = UInt32(bytes[10]) | UInt32(bytes[11]) << 8
        let serial = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[12+$1]) << ($1*8) }
        var name: String?
        for offset in stride(from: 54, through: 108, by: 18) {
            if bytes[offset] == 0 && bytes[offset+1] == 0 && bytes[offset+2] == 0 && bytes[offset+3] == 0xFC {
                let text = String(bytes: bytes[(offset+5)..<(offset+18)].prefix(while: { $0 != 10 && $0 != 0 }), encoding: .ascii)
                name = Monitor.cleanName(text)
            }
        }
        return EDIDIdentity(manufacturerCode: maker, vendorID: vendor, productID: product,
                            serialNumber: serial == 0 || serial == UInt32.max ? nil : serial, modelName: name)
    }
}

struct Monitor: Identifiable, Equatable {
    let id: String
    let name: String
    var manufacturerCode: String? = nil
    var vendorID: UInt32? = nil
    var productID: UInt32? = nil
    var serialNumber: UInt32? = nil
    var serialText: String? = nil
    var edidUUID: String? = nil
    var edidData: Data? = nil
    var edid: EDIDIdentity? {
        guard let data = edidData, let parsed = EDIDIdentity.parse(data) else { return nil }
        if let vendorID, vendorID != 0, vendorID != parsed.vendorID { return nil }
        if let productID, productID != 0, productID != parsed.productID { return nil }
        if let serialNumber, serialNumber != 0, serialNumber != UInt32.max,
           let edidSerial = parsed.serialNumber, serialNumber != edidSerial { return nil }
        return parsed
    }
    var resolvedVendorID: UInt32? { edid?.vendorID ?? vendorID }
    var resolvedProductID: UInt32? { edid?.productID ?? productID }
    var resolvedManufacturer: String? {
        if let code = edid?.manufacturerCode ?? manufacturerCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty { return code.uppercased() }
        if resolvedVendorID == 0x1E6D { return "GSM" }
        return nil
    }
    var manufacturerName: String {
        switch resolvedManufacturer {
        case "GSM": return "LG"
        case "APP": return "Apple"
        default:
            if let code = resolvedManufacturer { return code }
            if let vendor = resolvedVendorID, vendor != 0 { return String(format: "제조사 %04X", vendor) }
            return "알 수 없는 제조사"
        }
    }
    var modelKey: String? {
        guard let vendor = resolvedVendorID, let product = resolvedProductID, vendor != 0, product != 0 else { return nil }
        return String(format: "%04X:%04X", vendor, product)
    }
    var displayName: String {
        if let model = edid?.modelName ?? Self.cleanName(name) { return model }
        if let product = resolvedProductID, product != 0 { return String(format: "%@ · 제품 %04X", manufacturerName, product) }
        return manufacturerName == "알 수 없는 제조사" ? "외부 모니터" : "\(manufacturerName) 모니터"
    }
    // Kept for legacy display-name compatibility tests.
    var prefersLGAlternate: Bool { name.uppercased().hasPrefix("LG ") || name.uppercased() == "LG" }
    static func cleanName(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !["", "(null)", "unknown", "unknown display", "display", "generic pnp monitor"].contains(cleaned.lowercased()) else { return nil }
        return cleaned
    }
}

enum DisplayNames {
    static func labels(_ monitors: [Monitor]) -> [String: String] {
        let groups = Dictionary(grouping: monitors, by: { $0.displayName })
        var result: [String: String] = [:]
        for (name, group) in groups {
            for (index, monitor) in group.sorted(by: { $0.id < $1.id }).enumerated() {
                result[monitor.id] = group.count > 1 ? "\(name) · 모니터 \(index + 1)" : name
            }
        }
        return result
    }
}

enum ProfileMethod: String, Codable, CaseIterable {
    case standard, lgAlternate
    var label: String { self == .standard ? "일반 DDC" : "LG input-alt" }
}
struct ControlProfile: Equatable {
    let method: ProfileMethod
    let inputValues: [String: Int]
    func value(_ input: InputSource) -> Int { inputValues[input.rawValue] ?? input.value(alternate: method == .lgAlternate) }
    func arguments(uuid: String, input: InputSource) throws -> [String] {
        guard UUID(uuidString: uuid) != nil else { throw DDCError.message("유효하지 않은 모니터 UUID입니다.") }
        let number = value(input)
        guard (0...65535).contains(number) else { throw DDCError.message("입력 값은 0~65535의 정수여야 합니다.") }
        return ["display", "uuid=\(uuid)", "set", method == .lgAlternate ? "input-alt" : "input", String(number)]
    }
    static func defaults(_ method: ProfileMethod) -> ControlProfile {
        ControlProfile(method: method, inputValues: Dictionary(uniqueKeysWithValues: InputSource.allCases.map { ($0.rawValue, $0.value(alternate: method == .lgAlternate)) }))
    }
}
struct UserProfileOverride: Codable, Equatable {
    var method: ProfileMethod?
    var inputValues: [String: Int] = [:]
}
struct ResolvedProfile: Equatable {
    let profile: ControlProfile
    let source: String
}
enum ProfileResolver {
    // A configuration preset for the original LG setup, not an assertion of model-wide support.
    static let modelProfiles: [String: ControlProfile] = ["1E6D:7750": .defaults(.lgAlternate)]
    static func resolve(_ monitor: Monitor, user: UserProfileOverride? = nil, legacyAlternate: Bool? = nil,
                        models: [String: ControlProfile] = modelProfiles) -> ResolvedProfile {
        let baseline: ResolvedProfile
        if let key = monitor.modelKey, let model = models[key] {
            baseline = ResolvedProfile(profile: model, source: "모델 프로필 · \(key)")
        } else if monitor.resolvedManufacturer == "GSM" {
            baseline = ResolvedProfile(profile: .defaults(.lgAlternate), source: "제조사 기본값 · LG")
        } else {
            baseline = ResolvedProfile(profile: .defaults(.standard), source: "일반 DDC 기본값")
        }
        let method = user?.method ?? legacyAlternate.map { $0 ? ProfileMethod.lgAlternate : .standard } ?? baseline.profile.method
        // Switching methods resets port defaults; unrelated manufacturer values must not leak into the other protocol.
        let starting = method == baseline.profile.method ? baseline.profile : .defaults(method)
        var values = starting.inputValues
        if let overrides = user?.inputValues {
            for (key, value) in overrides where InputSource(rawValue: key) != nil && (0...65535).contains(value) { values[key] = value }
        }
        let hasOverride = user?.method != nil || user?.inputValues.contains(where: { InputSource(rawValue: $0.key) != nil && (0...65535).contains($0.value) }) == true
        return ResolvedProfile(profile: ControlProfile(method: method, inputValues: values),
                               source: hasOverride ? "사용자 저장 설정" : legacyAlternate != nil ? "사용자 저장 설정 · 기존 LG 옵션" : baseline.source)
    }
}

enum JSONDisplayParser {
    private struct Envelope: Decodable { let schemaVersion: Int; let displays: [Entry] }
    private struct Entry: Decodable {
        let uuid: String
        let name: String?
        let manufacturer: String?
        let vendorID: UInt32?
        let productID: UInt32?
        let serialNumber: UInt32?
        let serialText: String?
        let edidUUID: String?
        let edidBase64: String?
    }
    static func parse(_ text: String) throws -> [Monitor] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
        guard envelope.schemaVersion == 1 else { throw DDCError.message("지원하지 않는 모니터 정보 형식입니다.") }
        var seen = Set<String>()
        return try envelope.displays.map { entry in
            guard let uuid = UUID(uuidString: entry.uuid)?.uuidString, seen.insert(uuid).inserted else {
                throw DDCError.message("유효하지 않거나 중복된 모니터 UUID입니다.")
            }
            return Monitor(id: uuid, name: entry.name ?? "", manufacturerCode: entry.manufacturer, vendorID: entry.vendorID,
                           productID: entry.productID, serialNumber: entry.serialNumber, serialText: entry.serialText,
                           edidUUID: entry.edidUUID, edidData: entry.edidBase64.flatMap { Data(base64Encoded: $0) })
        }
    }
}

enum MonitorPower: Int, CaseIterable, Identifiable {
    case on = 1, standby = 2, suspend = 3, off = 4, hardOff = 5
    var id: Int { rawValue }
    static let offModes: [MonitorPower] = [.off, .standby, .suspend, .hardOff]
    var label: String {
        switch self {
        case .on: return "켜기 (1)"
        case .off: return "소프트 전원 끄기 (4) · 기본"
        case .standby: return "절전 (2)"
        case .suspend: return "일시 중단 (3)"
        case .hardOff: return "하드 전원 끄기 (5) · 기존 방식"
        }
    }
    func arguments(uuid: String) -> [String] {
        ["display", "uuid=\(uuid)", "set", "standby", String(rawValue)]
    }
}

enum PowerVerification: Equatable {
    case reported(MonitorPower)
    case unavailable
    static func parse(_ result: CommandResult) -> PowerVerification {
        guard result.status == 0, let number = Int(result.output), let mode = MonitorPower(rawValue: number) else { return .unavailable }
        return .reported(mode)
    }
}

enum InputSource: String, CaseIterable, Codable, Identifiable {
    case hdmi1 = "HDMI 1", hdmi2 = "HDMI 2", dp1 = "DP 1", dp2 = "DP 2", usbC = "USB-C"
    var id: String { rawValue }
    func value(alternate: Bool) -> Int {
        switch (self, alternate) {
        case (.hdmi1, false): return 17
        case (.hdmi2, false): return 18
        case (.dp1, false): return 15
        case (.dp2, false): return 16
        case (.usbC, false): return 27
        case (.hdmi1, true): return 144
        case (.hdmi2, true): return 145
        case (.dp1, true): return 208
        case (.dp2, true): return 209
        case (.usbC, true): return 210
        }
    }
    func arguments(uuid: String, alternate: Bool) -> [String] {
        ["display", "uuid=\(uuid)", "set", alternate ? "input-alt" : "input", String(value(alternate: alternate))]
    }
}

enum DisplayParser {
    static func parse(_ output: String) -> [Monitor] {
        let pattern = #"^\[\d+\] (.+) \(([0-9A-Fa-f-]{36})\)$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        return output.components(separatedBy: .newlines).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let idRange = Range(match.range(at: 2), in: line), UUID(uuidString: String(line[idRange])) != nil else { return nil }
            return Monitor(id: String(line[idRange]).uppercased(), name: String(line[nameRange]))
        }
    }
}

struct CommandResult {
    let status: Int32
    let output: String
}

enum DDCError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

// Serialized off the main actor. File-backed output avoids pipe-buffer deadlocks.
actor DDCService {
    let executable: URL
    init(executable: URL) { self.executable = executable }
    func run(_ arguments: [String], timeout: TimeInterval = 8) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DDCError.message("앱에 포함된 m1ddc를 찾을 수 없습니다. 앱을 다시 빌드하거나 설치하세요.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("output")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        if ended.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if ended.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = ended.wait(timeout: .now() + 1)
            }
            throw DDCError.message("모니터 응답 시간이 초과되었습니다. 케이블과 DDC/CI 설정을 확인하세요.")
        }
        let data = try Data(contentsOf: outputURL)
        return CommandResult(status: process.terminationStatus, output: String(decoding: data.prefix(65536), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func displays() throws -> [Monitor] {
        let result = try run(["display", "list", "json"])
        if result.output.contains("No external display found") { return [] }
        guard result.status == 0 else { throw DDCError.message(result.output) }
        let displays = try JSONDisplayParser.parse(result.output)
        return displays
    }
    func diagnostics(uuid: String) throws -> String {
        guard UUID(uuidString: uuid) != nil else { throw DDCError.message("유효하지 않은 모니터 UUID입니다.") }
        var lines = ["Pixovolt DDC 진단", "입력·전원 설정은 변경하지 않은 조회 결과입니다."]
        for feature in ["luminance", "input", "input-alt", "standby"] {
            do {
                let result = try run(["display", "uuid=\(uuid)", "get", feature])
                lines.append("get \(feature): exit=\(result.status), \(result.output)")
            } catch { lines.append("get \(feature): \(error.localizedDescription)") }
        }
        lines.append("입력 조회 값은 일부 LG 모델에서 고정값/비표준 응답일 수 있습니다. 현재 입력으로 확정하지 마세요.")
        return lines.joined(separator: "\n")
    }
    func setPower(uuid: String, power: MonitorPower) throws -> PowerVerification {
        guard UUID(uuidString: uuid) != nil else { throw DDCError.message("유효하지 않은 모니터 UUID입니다.") }
        let result = try run(power.arguments(uuid: uuid))
        guard result.status == 0, result.output == "Writing \(power.rawValue)" else {
            throw DDCError.message(result.output.isEmpty ? "전원 명령 전송에 실패했습니다." : result.output)
        }
        // Query once after a short settling period. No automatic fallback writes.
        Thread.sleep(forTimeInterval: 0.65)
        guard let read = try? run(["display", "uuid=\(uuid)", "get", "standby"], timeout: 3) else { return .unavailable }
        return PowerVerification.parse(read)
    }
    func switchInput(uuid: String, input: InputSource, alternate: Bool) throws {
        try switchInput(uuid: uuid, input: input, profile: .defaults(alternate ? .lgAlternate : .standard))
    }
    func switchInput(uuid: String, input: InputSource, profile: ControlProfile) throws {
        let arguments = try profile.arguments(uuid: uuid, input: input)
        let result = try run(arguments)
        guard result.status == 0, result.output == "Writing \(profile.value(input))" else {
            throw DDCError.message(result.output.isEmpty ? "입력 전환 명령이 실패했습니다." : result.output)
        }
    }
}
