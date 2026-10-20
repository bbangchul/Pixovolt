import Foundation

@main struct Tests {
    static func main() async throws {
        let uuid = "10ACB8A0-0000-0000-1419-0104A2435078"
        if CommandLine.arguments.contains("--probe-displays") {
            let displays = try await DisplayConnectionService().availableDisplays()
            for display in displays { print("uuid=\(display.uuid) builtIn=\(display.builtIn) active=\(display.active) online=\(display.online)") }
            return
        }
        let internalDisplay = ConnectionDisplay(id: 1, uuid: "00000000-0000-0000-0000-000000000001", builtIn: true, active: true, online: true, physical: true)
        let externalDisplay = ConnectionDisplay(id: 2, uuid: uuid, builtIn: false, active: true, online: true, physical: true, vendor: 1000, model: 2000, serial: 3000)
        _ = try ConnectionPolicy.target(uuid: uuid, in: [internalDisplay, externalDisplay], enabling: false)
        do { _ = try ConnectionPolicy.target(uuid: uuid, in: [externalDisplay], enabling: false); fatalError("only screen disabled") } catch {}
        do { _ = try ConnectionPolicy.target(uuid: internalDisplay.uuid, in: [internalDisplay, externalDisplay], enabling: false); fatalError("built-in disabled") } catch {}
        do { _ = try ConnectionPolicy.target(uuid: uuid, in: [internalDisplay, externalDisplay, externalDisplay], enabling: false); fatalError("ambiguous target accepted") } catch {}
        let offline = ConnectionDisplay(id: 9, uuid: "", builtIn: false, active: false, online: false, physical: true, vendor: 1000, model: 2000, serial: 3000)
        let recovered = try ConnectionPolicy.target(uuid: uuid, in: [offline], enabling: true, fallback: externalDisplay.identity)
        precondition(recovered.id == 9)
        do { _ = try ConnectionPolicy.target(uuid: uuid, in: [offline, offline], enabling: true, fallback: externalDisplay.identity); fatalError("ambiguous fallback accepted") } catch {}
        do { _ = try ConnectionPolicy.target(uuid: "not-a-uuid", in: [internalDisplay, externalDisplay], enabling: true); fatalError("bad identity accepted") } catch {}
        let listed = DisplayParser.parse("[1] LG (UltraFine) (\(uuid))\n - Display ID: 1\n[2] Bad (not-a-uuid)")
        precondition(listed == [Monitor(id: uuid, name: "LG (UltraFine)")])
        precondition(DisplayParser.parse("").isEmpty)
        precondition(Monitor(id: uuid, name: "LG HDR 4K").prefersLGAlternate)
        precondition(!Monitor(id: uuid, name: "DELL U2720Q").prefersLGAlternate)
        precondition(MonitorPower.off.arguments(uuid: uuid) == ["display", "uuid=\(uuid)", "set", "standby", "4"])
        precondition(MonitorPower.on.arguments(uuid: uuid) == ["display", "uuid=\(uuid)", "set", "standby", "1"])
        for mode in MonitorPower.allCases {
            precondition(mode.arguments(uuid: uuid).last == String(mode.rawValue))
        }
        precondition(PowerVerification.parse(CommandResult(status: 0, output: "1")) == .reported(.on))
        precondition(PowerVerification.parse(CommandResult(status: 0, output: "4")) == .reported(.off))
        precondition(PowerVerification.parse(CommandResult(status: 0, output: "2809")) == .unavailable)
        precondition(PowerVerification.parse(CommandResult(status: 1, output: "4")) == .unavailable)
        let normal = [17,18,15,16,27], alternate = [144,145,208,209,210]
        for (i, input) in InputSource.allCases.enumerated() {
            precondition(input.value(alternate: false) == normal[i])
            precondition(input.value(alternate: true) == alternate[i])
            precondition(input.arguments(uuid: uuid, alternate: true) == ["display", "uuid=\(uuid)", "set", "input-alt", "\(alternate[i])"])
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        func fixture(_ name: String, _ content: String) throws -> DDCService {
            let url = temp.appendingPathComponent(name)
            try ("#!/bin/sh\n" + content).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return DDCService(executable: url)
        }
        let success = try fixture("success", "echo \"Writing 17\"\n")
        try await success.switchInput(uuid: uuid, input: .hdmi1, alternate: false)
        let misleading = try fixture("misleading", "echo 'Writing 170'\n")
        do { try await misleading.switchInput(uuid: uuid, input: .hdmi1, alternate: false); fatalError("substring accepted") } catch {}
        let powerOff = try fixture("powerOff", "[ \"$*\" = 'display uuid=\(uuid) set standby 4' ] || exit 1\necho 'Writing 4'\n")
        let noReadback = try await powerOff.setPower(uuid: uuid, power: .off)
        precondition(noReadback == .unavailable)
        let ignored = try fixture("ignoredPower", "case \"$3\" in set) echo 'Writing 4';; get) echo '1';; *) exit 1;; esac\n")
        let unchanged = try await ignored.setPower(uuid: uuid, power: .off)
        precondition(unchanged == .reported(.on))
        let sleeping = try fixture("sleepingPower", "case \"$3\" in set) echo 'Writing 2';; get) echo '2';; *) exit 1;; esac\n")
        let state = try await sleeping.setPower(uuid: uuid, power: .standby)
        precondition(state == .reported(.standby))
        let powerOn = try fixture("powerOn", "[ \"$*\" = 'display uuid=\(uuid) set standby 1' ] || exit 1\necho 'Writing 1'\n")
        _ = try await powerOn.setPower(uuid: uuid, power: .on)
        do { _ = try await powerOff.setPower(uuid: "invalid", power: .off); fatalError("invalid UUID accepted") } catch {}
        let failure = try fixture("failure", "echo 'DDC communication failure'\nexit 1\n")
        do { try await failure.switchInput(uuid: uuid, input: .hdmi1, alternate: false); fatalError("failure accepted") }
        catch { precondition(error.localizedDescription.contains("DDC communication failure")) }
        do { _ = try await failure.setPower(uuid: uuid, power: .off); fatalError("power failure accepted") } catch {}
        let report = try await success.diagnostics(uuid: uuid)
        precondition(report.contains("get luminance:"))
        precondition(report.contains("get input-alt:"))
        let empty = try fixture("empty", "echo 'No external display found, aborting'\nexit 1\n")
        let displays = try await empty.displays()
        precondition(displays.isEmpty)
        let hangs = try fixture("hangs", "exec /bin/sleep 5\n")
        let start = Date()
        do { _ = try await hangs.run([], timeout: 0.1); fatalError("timeout accepted") }
        catch { precondition(Date().timeIntervalSince(start) < 3) }
        let missing = DDCService(executable: temp.appendingPathComponent("missing"))
        do { _ = try await missing.run([]); fatalError("missing accepted") } catch {}
        print("PASS: connection target/last-screen guard/built-in guard/duplicate rejection/fresh-ID recovery/ambiguous recovery rejection, power values 1-5, unchanged-on verification, standby verification, unavailable readback, LG default selection, power off/on arguments and execution, power failure, UUID validation, diagnostics, strict write result, parser, all 10 input mappings, UUID arguments, command success/failure, empty list, timeout termination, missing helper")
    }
}
