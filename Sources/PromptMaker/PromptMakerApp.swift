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
        _ = AppContext.shared
        Diagnostics.log("AppContext initialized, accessibility=\(AccessibilityHelper.isTrusted)")
        if !AccessibilityHelper.isTrusted {
            // Prompt user; this opens the System Settings dialog the first time.
            AccessibilityHelper.promptIfNeeded()
        }
    }
}

@MainActor
final class AppContext {
    static let shared = AppContext()

    let promptStore: PromptStore
    let historyStore: HistoryStore
    let floatingPanel: FloatingPanel
    let hotkeyManager: HotkeyManager
    private var settingsWindow: NSWindow?

    private init() {
        let promptStore = PromptStore()
        let historyStore = HistoryStore()
        let panel = FloatingPanel(promptStore: promptStore, historyStore: historyStore)
        self.promptStore = promptStore
        self.historyStore = historyStore
        self.floatingPanel = panel
        self.hotkeyManager = HotkeyManager(panel: panel)
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
