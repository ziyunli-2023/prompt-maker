import SwiftUI
import AppKit

@main
struct PromptMakerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("PromptMaker", systemImage: "sparkles") {
            Button("打开") {
                AppContext.shared.floatingPanel.show()
            }
            .keyboardShortcut("o")

            Button("设置…") {
                AppContext.shared.openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("退出") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Diagnostics.log("applicationDidFinishLaunching — initializing AppContext")
        // Prompt for Accessibility BEFORE initializing the hotkey manager.
        // This gives the user a chance to grant permission so the global
        // monitor works on first registration.
        if !AccessibilityHelper.isTrusted {
            AccessibilityHelper.promptIfNeeded()
        }
        _ = AppContext.shared
        Diagnostics.log("AppContext initialized, accessibility=\(AccessibilityHelper.isTrusted)")
    }
}

@MainActor
final class AppContext {
    static let shared = AppContext()

    let promptStore: PromptStore
    let historyStore: HistoryStore
    let floatingPanel: FloatingPanel
    let inputPanel: InputPanel
    let resultPanel: ResultPreviewPanel
    let hotkeyManager: HotkeyManager
    let selectionMonitor: SelectionMonitor
    private var settingsWindow: NSWindow?

    private init() {
        let promptStore = PromptStore()
        let historyStore = HistoryStore()
        let panel = FloatingPanel(promptStore: promptStore, historyStore: historyStore)
        let resultPanel = ResultPreviewPanel(historyStore: historyStore)
        let inputPanel = InputPanel(historyStore: historyStore, resultPanel: resultPanel)

        self.promptStore = promptStore
        self.historyStore = historyStore
        self.floatingPanel = panel
        self.resultPanel = resultPanel
        self.inputPanel = inputPanel
        self.hotkeyManager = HotkeyManager { [weak inputPanel] in
            inputPanel?.toggleStandalone()
        }
        self.selectionMonitor = SelectionMonitor(
            historyStore: historyStore,
            inputPanel: inputPanel,
            resultPanel: resultPanel
        )
    }

    func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "PromptMaker 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
