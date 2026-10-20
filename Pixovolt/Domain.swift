import Foundation

struct Monitor: Identifiable, Equatable {
    let id: String
    let name: String
    var prefersLGAlternate: Bool { name.uppercased().hasPrefix("LG ") || name.uppercased() == "LG" }
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
        let result = try run(["display", "list"])
        if result.output.contains("No external display found") { return [] }
        guard result.status == 0 else { throw DDCError.message(result.output) }
        let displays = DisplayParser.parse(result.output)
        if displays.isEmpty && !result.output.isEmpty { throw DDCError.message("모니터 목록을 해석하지 못했습니다: \(result.output)") }
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
        guard UUID(uuidString: uuid) != nil else { throw DDCError.message("유효하지 않은 모니터 UUID입니다.") }
        let result = try run(input.arguments(uuid: uuid, alternate: alternate))
        guard result.status == 0, result.output == "Writing \(input.value(alternate: alternate))" else {
            throw DDCError.message(result.output.isEmpty ? "입력 전환 명령이 실패했습니다." : result.output)
        }
    }
}
