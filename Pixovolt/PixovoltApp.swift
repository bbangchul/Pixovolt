import SwiftUI
import ServiceManagement

@main struct PixovoltApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Pixovolt", id: "control") {
            ControlPanel(model: model)
        }
        .windowResizability(.contentSize)
        MenuBarExtra("Pixovolt", systemImage: "display.2") {
            ControlMenu()
        }
    }
}

struct ControlMenu: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("제어 창 열기") {
            openWindow(id: "control")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Pixovolt 종료") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

struct ControlPanel: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false
    @State private var confirmScreenOff = false
    @State private var confirmDisconnect = false
    var body: some View {
        VStack(spacing: 0) {
        HStack {
            Label("Pixovolt", systemImage: "display.2").font(.headline)
            Spacer()
            Button("앱 종료") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }.padding(14)
        Divider()
        VStack(alignment: .leading, spacing: 5) {
            Text(model.busy ? "명령 실행 중…" : (model.error == nil ? "최근 결과" : "작업 오류"))
                .font(.caption.bold())
            Text(model.error ?? model.message)
                .font(.caption).foregroundStyle(model.error == nil ? Color.secondary : Color.orange)
                .lineLimit(4).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
        Divider()
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "display.2").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Pixovolt").font(.headline)
                    Text("모니터 입력 전환").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("모니터 새로 고침").disabled(model.busy)
            }
            Divider()
            if model.monitors.isEmpty {
                Label("외부 모니터를 찾지 못했습니다", systemImage: "display.trianglebadge.exclamationmark")
                Text("케이블을 연결한 뒤 새로 고침하세요. DisplayLink·AirPlay·일부 허브는 지원되지 않을 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("대상 모니터", selection: $model.selectedID) {
                    if !model.monitors.contains(where: { $0.id == model.selectedID }) {
                        Text("저장된 모니터 연결 끊김").tag(model.selectedID)
                    }
                    ForEach(model.monitors) { monitor in
                        Text("\(monitor.name) · \(monitor.id.prefix(8))").tag(monitor.id)
                    }
                }.disabled(model.busy)
                ForEach(Array(InputSource.allCases.enumerated()), id: \.element.id) { index, input in
                    Button { model.switchInput(input) } label: {
                        HStack {
                            Image(systemName: input == .usbC ? "cable.connector" : "display")
                            Text(input.rawValue)
                            Spacer()
                            if model.keysRegistered {
                                Text("\(["⌃⌥", "⌘⌥", "⌃⌘"][model.modifierChoice])\(model.numberKeys[index])")
                                    .foregroundStyle(.secondary).font(.caption.monospaced())
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.disabled(model.busy || !model.monitors.contains(where: { $0.id == model.selectedID }))
                }
                Text(model.alternate ? "현재 방식: LG input-alt (LG 모니터 기본값)" : "현재 방식: 일반 DDC input")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("LG 대체 방식 (input-alt)", isOn: Binding(get: { model.alternate }, set: { model.alternate = $0 }))
                    .disabled(model.busy)
                Text("이 모니터에만 저장됩니다. 변화가 없으면 아래 ‘다른 방식으로 재시도’를 누르세요. USB-C 값은 모델에 따라 다를 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 6) {
                    Label("작업을 완료하지 못했습니다", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("오류 복사") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(error, forType: .string) }
                        Button("닫기") { model.error = nil }
                    }
                }.padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text(model.message).font(.caption).foregroundStyle(.secondary)
            }
            if model.lastInput != nil {
                Text("최근 명령: \(model.lastCommand)").font(.caption).textSelection(.enabled)
                Button(model.lastUsedAlternate ? "일반 방식으로 재시도" : "LG 방식으로 재시도") { model.retryOtherMethod() }
                    .disabled(!model.canRetryOtherMethod)
            }
            HStack {
                Button("DDC 응답 진단") { model.diagnose() }.disabled(model.busy || !model.hasSelectedMonitor)
                if !model.diagnosticReport.isEmpty {
                    Button("진단 결과 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.diagnosticReport, forType: .string)
                    }
                }
            }
            if !model.diagnosticReport.isEmpty {
                DisclosureGroup("진단 결과 보기") {
                    Text(model.diagnosticReport).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            DisclosureGroup("단축키 및 자동 실행", isExpanded: $showSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("전역 단축키 사용", isOn: $model.shortcutEnabled)
                    Picker("조합", selection: $model.modifierChoice) {
                        ForEach(0..<AppModel.modifierNames.count, id: \.self) { Text(AppModel.modifierNames[$0]).tag($0) }
                    }
                    ForEach(Array(InputSource.allCases.enumerated()), id: \.element.id) { index, input in
                        Picker(input.rawValue, selection: Binding(get: { model.numberKeys[index] }, set: { model.numberKeys[index] = $0 })) {
                            ForEach(1...9, id: \.self) { Text(String($0)).tag($0) }
                        }
                    }
                    Text("선택한 모니터에 적용됩니다. 같은 숫자는 중복 지정할 수 없습니다.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("로그인 시 자동 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    Text(model.loginStatus).font(.caption).foregroundStyle(.secondary)
                    Button("로그인 항목 시스템 설정 열기") { SMAppService.openSystemSettingsLoginItems() }
                }.padding(.top, 10)
            }
            Divider()
            HStack {
                Button("오픈소스 라이선스") { model.showLicense() }.buttonStyle(.link)
                Spacer()
            }
            Text("v1.1.4 · Apple Silicon · 실제 모니터 호환성 확인 필요")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 390)
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Button("외부 화면 끄기 (Mac 연결 해제)") { confirmDisconnect = true }
                .disabled(model.busy || !model.hasSelectedMonitor)
            ForEach(model.disconnectedTargets.keys.sorted(), id: \.self) { target in
                Button("\(model.disconnectedTargets[target] ?? "외부 화면") 다시 연결") { model.reconnect(target) }
                    .disabled(model.busy)
            }
            Text("내장 화면이 켜져 있을 때만 해제합니다. 창이 노트북으로 이동하며 다른 본체로 입력이 전환될 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("고급: DDC 전원 끄기 · 호환성 제한") {
            Picker("끄기 방식", selection: Binding(get: { model.offMode }, set: { model.offMode = $0 })) {
                ForEach(MonitorPower.offModes) { Text($0.label).tag($0) }
            }.disabled(model.busy)
            HStack {
                Button { confirmScreenOff = true } label: { Label("기존 DDC 전원 명령 전송", systemImage: "power") }
                    .disabled(model.busy || !model.hasSelectedMonitor)
                Button("DDC 켜기 시도") { model.setPower(.on) }
                    .disabled(model.busy || (model.sleepingTargetID == nil && !model.hasSelectedMonitor))
                Spacer()
            }
            Text("이 모니터에서는 DDC 끄기 2/3/4/5가 작동하지 않는다고 보고됐습니다. 위의 Mac 연결 해제 버튼을 사용하세요.")
                .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14)
        }
        .frame(width: 390, height: showSettings ? 740 : 690)
        .alert("외부 화면을 이 Mac에서 연결 해제할까요?", isPresented: $confirmDisconnect) {
            Button("연결 해제", role: .destructive) { model.disconnectSelected() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("모니터 물리 전원 끄기와 다릅니다. 창은 내장 화면으로 이동합니다. 앱에서 다시 연결할 수 있고 복구 실패 시 케이블을 분리 후 연결하세요.")
        }
        .confirmationDialog("선택한 외부 모니터 화면을 끌까요?", isPresented: $confirmScreenOff) {
            Button("화면 끄기", role: .destructive) { model.setPower(model.offMode) }
            Button("취소", role: .cancel) { }
        } message: {
            Text("선택 방식: \(model.offMode.label). 다시 켤 때 모니터 물리 버튼이 필요할 수 있습니다. 앱 종료는 화면을 끄지 않습니다.")
        }
        .onAppear { model.updateLoginStatus(); model.refresh() }
    }
}
