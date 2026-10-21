import SwiftUI
import ServiceManagement
import Carbon

@MainActor final class AppModel: ObservableObject {
    @Published var monitors: [Monitor] = []
    @Published var selectedID: String { didSet { defaults.set(selectedID, forKey: "selectedID"); profileValidationError = nil } }
    @Published var alternateIDs: [String: Bool] { didSet { defaults.set(alternateIDs, forKey: "alternateIDs") } }
    @Published var powerModeIDs: [String: Int] { didSet { defaults.set(powerModeIDs, forKey: "powerModeIDs") } }
    var offMode: MonitorPower {
        get {
            let mode = MonitorPower(rawValue: powerModeIDs[selectedID] ?? 4) ?? .off
            return mode == .on ? .off : mode
        }
        set { if newValue != .on { powerModeIDs[selectedID] = newValue.rawValue } }
    }
    @Published var disconnectedTargets: [String: String] { didSet { defaults.set(disconnectedTargets, forKey: "disconnectedTargets") } }
    private var connectionIdentities: [String: ConnectionIdentity] { didSet {
        if let data = try? JSONEncoder().encode(connectionIdentities) { defaults.set(data, forKey: "connectionIdentities") }
    } }
    private let connectionService = DisplayConnectionService()
    @Published var profileOverrides: [String: UserProfileOverride] { didSet {
        if let data = try? JSONEncoder().encode(profileOverrides) { defaults.set(data, forKey: "profileOverrides") }
    } }
    @Published var profileValidationError: String?
    var selectedMonitor: Monitor? { monitors.first { $0.id == selectedID } }
    func displayLabel(_ monitor: Monitor) -> String { DisplayNames.labels(monitors)[monitor.id] ?? monitor.displayName }
    var activeProfile: ResolvedProfile? {
        guard let selectedMonitor else { return nil }
        return ProfileResolver.resolve(selectedMonitor, user: profileOverrides[selectedID], legacyAlternate: alternateIDs[selectedID])
    }
    var profileChoice: String {
        get {
            if let method = profileOverrides[selectedID]?.method { return method.rawValue }
            if let legacy = alternateIDs[selectedID] { return (legacy ? ProfileMethod.lgAlternate : .standard).rawValue }
            return "automatic"
        }
        set {
            guard !busy, selectedMonitor != nil else { return }
            guard newValue != profileChoice else { return }
            // Automatic selection explicitly clears the legacy manual method too.
            alternateIDs.removeValue(forKey: selectedID)
            var edit = profileOverrides[selectedID] ?? UserProfileOverride()
            edit.method = ProfileMethod(rawValue: newValue)
            // Values belong to a protocol. Explicit method changes discard old custom port values.
            edit.inputValues = [:]
            profileOverrides[selectedID] = edit
            profileValidationError = nil
        }
    }
    func setProfileValue(_ input: InputSource, text: String) {
        guard !busy, selectedMonitor != nil else { return }
        guard let value = Int(text), (0...65535).contains(value) else {
            profileValidationError = "입력 값은 0~65535의 정수여야 합니다. 저장하지 않았습니다."
            return
        }
        var edit = profileOverrides[selectedID] ?? UserProfileOverride()
        if edit.method == nil { edit.method = activeProfile?.profile.method }
        edit.inputValues[input.rawValue] = value
        profileOverrides[selectedID] = edit
        profileValidationError = nil
    }
    func resetProfile() {
        guard !busy, selectedMonitor != nil else { return }
        profileOverrides.removeValue(forKey: selectedID)
        alternateIDs.removeValue(forKey: selectedID)
        profileValidationError = nil
    }
    @Published var busy = false
    @Published var message = "입력 전환 후 현재 Mac의 화면 연결이 끊길 수 있습니다."
    @Published var error: String?
    @Published var loginStatus = ""
    @Published var diagnosticReport = ""
    @Published var lastCommand = "아직 명령을 보내지 않았습니다."
    @Published var lastInput: InputSource?
    @Published var lastUsedAlternate = false
    @Published var lastTargetID: String?
    @Published var sleepingTargetID: String?
    @Published var shortcutEnabled: Bool { didSet { defaults.set(shortcutEnabled, forKey: "shortcutEnabled"); configureKeys() } }
    @Published var modifierChoice: Int { didSet { defaults.set(modifierChoice, forKey: "modifierChoice"); configureKeys() } }
    @Published var numberKeys: [Int] { didSet { defaults.set(numberKeys, forKey: "numberKeys"); configureKeys() } }
    @Published var keysRegistered = false
    private let defaults = UserDefaults.standard
    private let service: DDCService
    private let keys = HotKeys()
    private var observers: [NSObjectProtocol] = []
    private var refreshPending = false
    var alternate: Bool {
        get { activeProfile?.profile.method == .lgAlternate }
        set { profileChoice = (newValue ? ProfileMethod.lgAlternate : .standard).rawValue }
    }
    static let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    static let modifierNames = ["⌃⌥ (Control + Option)", "⌘⌥ (Command + Option)", "⌃⌘ (Control + Command)"]
    private static func migrateLegacyPreferences() {
        let preferences = UserDefaults.standard
        guard !preferences.bool(forKey: "didMigrateLegacyPreferences") else { return }
        let previous = preferences.persistentDomain(forName: "local.monitorswitch.app") ?? [:]
        let keys = ["selectedID", "alternateIDs", "shortcutEnabled", "modifierChoice", "numberKeys", "powerModeIDs", "disconnectedTargets", "connectionIdentities"]
        for key in keys where preferences.object(forKey: key) == nil {
            if let value = previous[key] { preferences.set(value, forKey: key) }
        }
        preferences.set(true, forKey: "didMigrateLegacyPreferences")
    }
    init() {
        Self.migrateLegacyPreferences()
        let profiles = UserDefaults.standard.data(forKey: "profileOverrides") ?? Data()
        profileOverrides = (try? JSONDecoder().decode([String: UserProfileOverride].self, from: profiles)) ?? [:]
        disconnectedTargets = UserDefaults.standard.dictionary(forKey: "disconnectedTargets") as? [String: String] ?? [:]
        let identityData = UserDefaults.standard.data(forKey: "connectionIdentities") ?? Data()
        connectionIdentities = (try? JSONDecoder().decode([String: ConnectionIdentity].self, from: identityData)) ?? [:]
        powerModeIDs = UserDefaults.standard.dictionary(forKey: "powerModeIDs") as? [String: Int] ?? [:]
        selectedID = UserDefaults.standard.string(forKey: "selectedID") ?? ""
        alternateIDs = UserDefaults.standard.dictionary(forKey: "alternateIDs") as? [String: Bool] ?? [:]
        shortcutEnabled = UserDefaults.standard.bool(forKey: "shortcutEnabled")
        modifierChoice = min(2, max(0, UserDefaults.standard.integer(forKey: "modifierChoice")))
        let saved = UserDefaults.standard.array(forKey: "numberKeys") as? [Int] ?? []
        numberKeys = saved.count == 5 && saved.allSatisfy({ (1...9).contains($0) }) ? saved : [1,2,3,4,5]
        service = DDCService(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/m1ddc"))
        keys.onPress = { [weak self] index in
            Task { @MainActor in
                guard InputSource.allCases.indices.contains(index) else { return }
                self?.switchInput(InputSource.allCases[index])
            }
        }
        configureKeys()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        updateLoginStatus()
        refresh()
    }
    func configureKeys() {
        keysRegistered = false
        keys.clear()
        guard shortcutEnabled else { return }
        let flags = [UInt32(controlKey | optionKey), UInt32(cmdKey | optionKey), UInt32(controlKey | cmdKey)]
        do {
            try keys.register(modifiers: flags[modifierChoice], keyCodes: numberKeys.map { Self.keyCodes[$0 - 1] })
            keysRegistered = true
        } catch { self.error = error.localizedDescription }
    }
    func refresh() {
        guard !busy else { refreshPending = true; return }
        busy = true
        Task {
            defer { finishOperation() }
            do {
                let found = try await service.displays()
                monitors = found
                // Only initial selection may default to the first display. A missing saved target stays missing.
                if selectedID.isEmpty { selectedID = found.first?.id ?? "" }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func finishOperation() {
        busy = false
        if refreshPending { refreshPending = false; refresh() }
    }
    func switchInput(_ input: InputSource) {
        guard !busy else { return }
        guard monitors.contains(where: { $0.id == selectedID }) else {
            error = "선택한 모니터가 연결되어 있지 않습니다. 모니터 목록에서 대상을 선택하세요."
            return
        }
        guard let profile = activeProfile?.profile else { return }
        // Capture the target and complete profile before asynchronous execution.
        let target = selectedID, useAlternate = profile.method == .lgAlternate
        busy = true
        error = nil
        lastInput = input
        lastTargetID = target
        lastUsedAlternate = useAlternate
        lastCommand = "\(input.rawValue) · \(useAlternate ? "LG input-alt" : "일반 input") · 값 \(profile.value(input))"
        Task {
            defer { finishOperation() }
            do {
                try await service.switchInput(uuid: target, input: input, profile: profile)
                message = "\(lastCommand) 전달됨. 화면 전환은 확인되지 않았습니다. 변화가 없으면 전환 방식을 바꿔 다시 시도하세요."
            } catch { self.error = "\(error.localizedDescription)\n모니터 OSD에서 DDC/CI를 켜고 케이블·허브 연결을 확인하세요." }
        }
    }
    var hasSelectedMonitor: Bool { monitors.contains { $0.id == selectedID } }
    var canRetryOtherMethod: Bool { lastInput != nil && lastTargetID == selectedID && hasSelectedMonitor && !busy }
    func retryOtherMethod() {
        guard canRetryOtherMethod, let lastInput else { return }
        alternate = !lastUsedAlternate
        switchInput(lastInput)
    }
    func diagnose() {
        guard !busy, hasSelectedMonitor else { return }
        let target = selectedID
        let name = monitors.first { $0.id == target }?.displayName ?? "모니터"
        busy = true
        Task {
            defer { finishOperation() }
            do {
                diagnosticReport = "모니터: \(name)\n최근 명령: \(lastCommand)\n" + (try await service.diagnostics(uuid: target))
                message = "조회 진단이 완료되었습니다. 진단 결과 복사 버튼으로 결과를 복사할 수 있습니다."
            } catch { self.error = error.localizedDescription }
        }
    }
    func setPower(_ power: MonitorPower) {
        guard !busy else { return }
        // A sleeping monitor can disappear from the online list. Keep its UUID for a best-effort wake.
        let target = power == .on ? (sleepingTargetID ?? selectedID) : selectedID
        guard UUID(uuidString: target) != nil, power == .on || hasSelectedMonitor else {
            error = "먼저 모니터를 선택하세요."
            return
        }
        busy = true
        error = nil
        Task {
            defer { finishOperation() }
            do {
                let verification = try await service.setPower(uuid: target, power: power)
                lastCommand = "전원 · VCP 0xD6 · 값 \(power.rawValue)"
                if power != .on { sleepingTargetID = target }
                else { sleepingTargetID = nil }
                switch verification {
                case .reported(.on) where power != .on:
                    sleepingTargetID = nil
                    self.error = "모니터가 계속 켜짐(1) 상태를 보고했습니다. \(power.label) 명령이 무시되었거나 곧바로 복귀했습니다. 하단의 끄기 방식을 바꿔 다시 시도하세요."
                case .reported(let mode):
                    message = "\(power.label) 전송 후 모니터 응답: \(mode.label). 실제 화면 상태를 확인하세요."
                case .unavailable:
                    message = "\(power.label) 명령은 전달됐지만 이후 전원 상태를 읽지 못했습니다. 꺼졌는지는 화면에서 확인하세요."
                }
            } catch { self.error = "\(error.localizedDescription)\n절전 중 모니터는 DDC 명령에 응답하지 않을 수 있습니다. 물리 버튼으로 켜세요." }
        }
    }
    func disconnectSelected() {
        guard !busy, hasSelectedMonitor else { return }
        let target = selectedID
        let name = monitors.first { $0.id == target }?.displayName ?? "외부 모니터"
        busy = true
        error = nil
        Task {
            defer { finishOperation() }
            do {
                let identity = try await connectionService.identity(uuid: target)
                connectionIdentities[target] = identity
                // Persist recovery BEFORE sending the command, including when verification later fails.
                disconnectedTargets[target] = name
                try await connectionService.setEnabled(uuid: target, enabled: false, fallback: identity)
                message = "이 Mac에서 \(name) 연결을 해제했습니다. 물리 전원을 끈 것은 아닙니다. 아래에서 다시 연결할 수 있습니다."
                refreshPending = true
            } catch { self.error = error.localizedDescription }
        }
    }
    func reconnect(_ target: String) {
        guard !busy, disconnectedTargets[target] != nil else { return }
        busy = true
        error = nil
        let identity = connectionIdentities[target]
        Task {
            defer { finishOperation() }
            do {
                try await connectionService.setEnabled(uuid: target, enabled: true, fallback: identity)
                disconnectedTargets.removeValue(forKey: target)
                connectionIdentities.removeValue(forKey: target)
                selectedID = target
                message = "외부 모니터를 다시 연결했습니다."
                refreshPending = true
            } catch { self.error = "\(error.localizedDescription)\n복구되지 않으면 케이블을 분리 후 다시 연결하세요. 필요하면 로그아웃 후 로그인하세요." }
        }
    }
    func updateLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "로그인 시 자동 실행 켜짐"
        case .requiresApproval: loginStatus = "시스템 설정에서 로그인 항목 승인이 필요합니다"
        case .notRegistered: loginStatus = "로그인 시 자동 실행 꺼짐"
        case .notFound: loginStatus = "앱을 응용 프로그램 폴더에 설치하세요"
        @unknown default: loginStatus = "자동 실행 상태를 확인할 수 없습니다"
        }
    }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { self.error = "자동 실행 설정 실패: \(error.localizedDescription)" }
        updateLoginStatus()
    }
    func showLicense() {
        guard let url = Bundle.main.url(forResource: "m1ddc-LICENSE", withExtension: "txt") else { return }
        NSWorkspace.shared.open(url)
    }
}
