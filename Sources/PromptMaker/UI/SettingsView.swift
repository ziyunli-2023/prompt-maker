import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsView: View {
    @AppStorage("backend") private var backend: String = "deepseek"
    @AppStorage("autoFillFromClipboard") private var autoFill: Bool = true
    @AppStorage("selectionPopupEnabled") private var selectionPopup: Bool = true
    @AppStorage("geminiModel") private var geminiModel: String = ""
    @State private var geminiKey: String = KeychainHelper.shared.read(key: "geminiAPIKey") ?? ""
    @State private var deepseekKey: String = KeychainHelper.shared.read(key: "deepseekAPIKey") ?? ""
    @State private var cliStatus: CLIStatus = .checking
    @State private var hotkeySpec: HotkeySpec = HotkeyPrefs.load()
    @State private var isRecording: Bool = false
    @State private var monitor: Any?

    enum CLIStatus {
        case checking
        case ok(String)
        case missing
    }

    var body: some View {
        Form {
            Section("热键") {
                HStack {
                    Text("唤起悬浮窗")
                    Spacer()
                    Button {
                        toggleRecording()
                    } label: {
                        Text(isRecording ? "按下新组合…（Esc 取消）" : hotkeySpec.displayString)
                            .frame(minWidth: 160)
                            .padding(.horizontal, 6)
                    }
                }
                Text("点击右侧按钮再按新组合即可改键。修饰键 + 主键，至少包含一个 ⌘/⌥/⌃/⇧。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("后端") {
                Picker("使用", selection: $backend) {
                    Text("DeepSeek API（推荐）").tag("deepseek")
                    Text("Gemini CLI（账号登录）").tag("cli")
                    Text("Gemini API Key").tag("api")
                }
                .pickerStyle(.radioGroup)

                switch backend {
                case "deepseek":
                    SecureField("DeepSeek API Key", text: $deepseekKey)
                        .onChange(of: deepseekKey) { newValue in
                            KeychainHelper.shared.save(key: "deepseekAPIKey", value: newValue)
                        }
                    Link(
                        "从 DeepSeek 平台获取 API Key",
                        destination: URL(string: "https://platform.deepseek.com/api_keys")!
                    )
                    .font(.caption)
                case "cli":
                    cliStatusView
                default:
                    SecureField("Gemini API Key", text: $geminiKey)
                        .onChange(of: geminiKey) { newValue in
                            KeychainHelper.shared.save(key: "geminiAPIKey", value: newValue)
                        }
                    Link(
                        "从 Google AI Studio 获取 API Key",
                        destination: URL(string: "https://aistudio.google.com/apikey")!
                    )
                    .font(.caption)
                }

                TextField("模型（留空使用默认）", text: $geminiModel)
                    .help("DeepSeek 默认 deepseek-chat；Gemini CLI 走 CLI 默认；Gemini API 默认 gemini-2.0-flash")
            }

            Section("行为") {
                Toggle("唤起时自动从剪贴板预填", isOn: $autoFill)
                Toggle("选中文字后显示优化按钮", isOn: $selectionPopup)
                    .onChange(of: selectionPopup) { newValue in
                        AppContext.shared.selectionMonitor.setEnabled(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 480)
        .onAppear { checkCLI() }
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private var cliStatusView: some View {
        switch cliStatus {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在检测 gemini CLI…").font(.caption).foregroundStyle(.secondary)
            }
        case .ok(let path):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("已找到：\(path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .missing:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("未找到 gemini CLI").font(.caption).bold()
                }
                Text("请在 Terminal 安装并登录：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("npm install -g @google/gemini-cli\ngemini auth login")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
                Button("重新检测") { checkCLI() }
                    .controlSize(.small)
            }
        }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if Int(event.keyCode) == kVK_Escape {
                Task { @MainActor in self.stopRecording() }
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonMods = HotkeySpec.carbonModifiers(from: flags)
            guard carbonMods != 0 else { return event }
            let spec = HotkeySpec(modifiers: carbonMods, keyCode: UInt32(event.keyCode))
            Task { @MainActor in
                self.hotkeySpec = spec
                AppContext.shared.hotkeyManager.rebind(to: spec)
                self.stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func checkCLI() {
        cliStatus = .checking
        Task.detached {
            let path = Self.locateGemini()
            await MainActor.run {
                cliStatus = path.map { .ok($0) } ?? .missing
            }
        }
    }

    nonisolated private static func locateGemini() -> String? {
        let fm = FileManager.default
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""

        var candidates: [String] = [
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini",
        ]
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            for v in versions {
                candidates.append("\(nvmRoot)/\(v)/bin/gemini")
            }
        }

        for p in candidates where fm.isExecutableFile(atPath: p) {
            return p
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", "which gemini"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, fm.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }
}
