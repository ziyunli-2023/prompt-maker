# PromptMaker

A lightweight macOS menu-bar app that turns Chinese/English mixed-language drafts into polished English prompts in one keystroke. It produces two outputs side-by-side — a faithful literal translation and a grammar-corrected, idiomatic version — and auto-copies the optimized version to your clipboard so you can paste it straight into Claude or ChatGPT.

## Features

- Menu bar only — no Dock icon
- Global hotkey to summon/dismiss the floating panel (default ⌃⌥P)
- Two-column result: **translation** (word-for-word faithful) + **optimized** (polished English)
- Both columns are editable; optimized auto-copies to clipboard on submit
- Up to 100 history entries, click any to restore
- Powered by DeepSeek API (`deepseek-chat`, temperature 0)

## Prerequisites

macOS 13 (Ventura) or later, Xcode Command Line Tools:

```sh
xcode-select --install
```

## Setup

1. **Add your API key** — copy the example secrets file and fill in your [DeepSeek API key](https://platform.deepseek.com/api_keys):

   ```sh
   cp Secrets.example.swift Sources/PromptMaker/Secrets.swift
   # edit Secrets.swift and replace the placeholder with your real key
   ```

2. **Build and run:**

   ```sh
   swift run -c release
   ```

   First build takes ~30 seconds. A ✨ icon appears in the menu bar.

3. **Grant Accessibility** when prompted (required for the global hotkey).

Press **⌃⌥P** to summon the panel:

- Input field auto-focuses; clipboard text is pre-filled if it's under 2000 characters (configurable)
- **⌘↩** to submit
- **Esc** to dismiss
- Top-right icons: history drawer, new entry, close

## Background / auto-start

`swift run -c release` is foreground. To keep it running:

**Option A — background process**
```sh
nohup .build/release/PromptMaker > /tmp/promptmaker.log 2>&1 &
```

**Option B — LaunchAgent (starts at login)**
```sh
cat > ~/Library/LaunchAgents/com.local.promptmaker.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.promptmaker</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(pwd)/.build/release/PromptMaker</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/promptmaker.log</string>
  <key>StandardErrorPath</key><string>/tmp/promptmaker.log</string>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.local.promptmaker.plist
```

To unload: `launchctl unload ~/Library/LaunchAgents/com.local.promptmaker.plist`

## Data locations

| What | Where |
|---|---|
| History | `~/Library/Application Support/PromptMaker/history.json` |
| Preferences | `~/Library/Preferences/PromptMaker.plist` |
| API key (if stored via Settings) | Keychain — service `PromptMaker`, account `deepseekAPIKey` |

## Optimization rules

The system prompt lives in `Sources/PromptMaker/Services/AICompletionService.swift` (`SYSTEM_PROMPT`). Current rules:

- Fix grammar, use idiomatic phrasing, use accurate terminology
- **Never** inject role framing (`You are an expert…`) or output-format instructions (`Output in markdown…`) not present in the source
- No added context, scope, or assumptions — only refine language
- Sentence count and length stay close to the original

## Project structure

```
Sources/PromptMaker/
├── PromptMakerApp.swift          # @main, MenuBarExtra, AppDelegate
├── Secrets.swift                 # gitignored — DeepSeek API key
├── Hotkey/
│   ├── HotkeyManager.swift       # NSEvent global/local monitors
│   └── HotkeySpec.swift          # Persistence + display string
├── UI/
│   ├── FloatingPanel.swift       # NSPanel (.floating, nonactivating)
│   ├── PromptView.swift          # Main interaction
│   └── SettingsView.swift        # Backend / hotkey / clipboard toggle
├── Services/
│   ├── AICompletionService.swift # Protocol + SYSTEM_PROMPT + JSON parsing
│   ├── DeepSeekService.swift     # URLSession → DeepSeek chat completions
│   ├── GeminiAPIService.swift    # Gemini API fallback
│   ├── GeminiCLIService.swift    # Gemini CLI fallback
│   └── ServiceFactory.swift      # Selects backend from UserDefaults
└── Storage/
    ├── PromptStore.swift         # @MainActor ObservableObject
    ├── HistoryStore.swift        # JSON persistence
    └── KeychainHelper.swift      # Keychain wrapper
Secrets.example.swift             # Copy → Sources/PromptMaker/Secrets.swift
Scripts/build_app.sh              # Wraps binary in .app bundle
```

## Known limitations

- Global hotkey requires Accessibility permission; macOS revokes it on every rebuild (ad-hoc codesign changes the hash). Use the menu bar icon as a workaround, or build a proper signed .app.
- No streaming output — single blocking request
- No iCloud sync, no multi-language UI, no in-place text substitution
