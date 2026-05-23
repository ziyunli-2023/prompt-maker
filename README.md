# PromptMaker ✨

**Select text anywhere on macOS. Get a polished English prompt in your clipboard. One keystroke. One click.**

PromptMaker is a tiny menu-bar app that turns rough, mixed Chinese/English drafts into clean, idiomatic English — ready to paste into Claude, ChatGPT, Gemini, or any LLM. It lives in your menu bar, weighs nothing, and disappears the moment you're done with it.

---

## Why you'll like it

- ⚡ **Two ways in, zero friction.** Hit a global hotkey (`⌘⇧M`) anywhere, or just *select text* in any app — Safari, Chrome, VS Code, Notes, Slack — and a ✨ icon pops up next to your cursor.
- 🪄 **Short click = instant magic.** Click ✨ once → text is optimized → auto-pasted back in place. The original mess is gone, the polished version is there. No window. No copy-paste dance.
- 🧠 **Long-press = "do whatever I say."** Hold ✨ for a beat and a tiny input pill appears: *"summarize in one sentence"*, *"rewrite as a Cursor prompt"*, *"translate to French"*. Type your instruction, hit Enter, done.
- 🔁 **Refine in place.** The result panel has a follow-up box — keep iterating without retyping your text.
- 📋 **Side-by-side translation.** For the default optimize flow, you see both a *literal* translation and the *idiomatic* one. Pick whichever you trust.
- 🕘 **Last 100 prompts, one keystroke away.** Click any entry to restore it.
- 🔌 **Pluggable backend.** Ships with DeepSeek (cheap, fast, great at Chinese). Swap in Gemini API or Gemini CLI from Settings without rebuilding.
- 🪶 **5 MB binary. No Electron. No background CPU.** Pure Swift + AppKit. Menu-bar only, no Dock clutter.

---

## The 60-second tour

```text
        ┌─────────────────────────────────────────────┐
        │  ⌘⇧M  anywhere  →  floating panel           │
        │                                             │
        │   ┌─────────────────────────────────────┐   │
        │   │ paste your messy draft here…       │   │
        │   └─────────────────────────────────────┘   │
        │                                             │
        │   ┌─── translation ───┬── optimized ───┐    │
        │   │ word-for-word      │ idiomatic EN  │    │
        │   │ faithful           │ ← clipboard   │    │
        │   └────────────────────┴───────────────┘    │
        └─────────────────────────────────────────────┘

   …or just  ⌃ drag-select text  →  ✨ pops up
                  ↳ click   → optimize + auto-paste
                  ↳ hold    → custom instruction
```

---

## Get started in 90 seconds

**Requirements:** macOS 13 (Ventura) or later, Xcode CLT (`xcode-select --install`).

```sh
# 1. Drop in your API key (DeepSeek is the default; ~$0.001 per prompt)
cp Secrets.example.swift Sources/PromptMaker/Secrets.swift
#    → edit Secrets.swift, paste your key from
#      https://platform.deepseek.com/api_keys

# 2. Build a proper .app bundle (needed for global hotkeys on Sequoia+)
./Scripts/build_app.sh release

# 3. Launch
open build/PromptMaker.app
```

A ✨ icon shows up in your menu bar. macOS will ask for **Accessibility** permission — grant it so the selection popup can read text from any app.

Press **⌘⇧M** anywhere. Type or paste something. Hit `⌘↩`. That's the whole product.

---

## Keystrokes

| Where | Key | What it does |
|---|---|---|
| anywhere | `⌘⇧M` | summon the floating panel (customizable in Settings) |
| panel | `⌘↩` | submit (optimized version auto-copies to clipboard) |
| panel | `Esc` | dismiss |
| selection ✨ | click | optimize + auto-paste over your selection |
| selection ✨ | long-press | open custom-instruction pill |
| result panel | type + `↩` | refine the result further |

---

## Want it always-on? (LaunchAgent)

```sh
cat > ~/Library/LaunchAgents/com.local.promptmaker.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.promptmaker</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(pwd)/build/PromptMaker.app/Contents/MacOS/PromptMaker</string>
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

Boots silently at login. Unload with `launchctl unload …` if you change your mind.

---

## Picking a backend

Open **Settings** from the menu-bar icon (or `⌘,` from the panel):

| Backend | Pros | Notes |
|---|---|---|
| **DeepSeek** (default) | cheap, fast, strong on Chinese↔English | needs API key |
| **Gemini API** | great general quality, free tier | needs API key |
| **Gemini CLI** | uses your local `gemini` install, no key in app | requires `gemini` on `PATH` |

API keys can live in `Secrets.swift` (build-time) or in **Keychain** via the Settings window (recommended).

---

## What it *won't* do to your prompt

PromptMaker is deliberately conservative. The system prompt (see `Sources/PromptMaker/Services/AICompletionService.swift`) enforces:

- ✅ Fix grammar, use idiomatic phrasing, accurate terminology
- ❌ **Never** add role framing (*"You are an expert…"*)
- ❌ **Never** add output-format instructions you didn't write (*"Output in markdown…"*)
- ❌ No invented context, no added scope, no hallucinated assumptions
- ✅ Sentence count and length stay close to the original

Your intent goes in, the same intent comes out — just sharper.

---

## Where your stuff lives

| | Path |
|---|---|
| History (last 100) | `~/Library/Application Support/PromptMaker/history.json` |
| Preferences | `~/Library/Preferences/PromptMaker.plist` |
| API key (Keychain) | service `PromptMaker`, account `deepseekAPIKey` |
| Diagnostic log | `/tmp/promptmaker.log` |

---

## Under the hood

```
Sources/PromptMaker/
├── PromptMakerApp.swift          @main · MenuBarExtra · AppDelegate
├── Hotkey/
│   ├── HotkeyManager.swift       Carbon RegisterEventHotKey (works on Sequoia)
│   └── HotkeySpec.swift          persisted shortcut + display string
├── UI/
│   ├── FloatingPanel.swift       main NSPanel (.floating, nonactivating)
│   ├── PromptView.swift          two-column input/output
│   ├── SelectionMonitor.swift    global mouse listener + AX text scraping
│   ├── PopupButton.swift         the ✨ icon (short click vs long press)
│   ├── InputPanel.swift          long-press instruction pill
│   ├── ResultPreviewPanel.swift  result + follow-up refinement
│   └── SettingsView.swift        backend, hotkey, clipboard prefill toggle
├── Services/
│   ├── AICompletionService.swift protocol + SYSTEM_PROMPT + JSON parsing
│   ├── DeepSeekService.swift     URLSession → DeepSeek chat completions
│   ├── GeminiAPIService.swift    Gemini REST
│   ├── GeminiCLIService.swift    subprocess to local `gemini` CLI
│   └── ServiceFactory.swift      chooses backend from UserDefaults
└── Storage/
    ├── PromptStore.swift         current-session state
    ├── HistoryStore.swift        JSON-on-disk persistence
    └── KeychainHelper.swift      Keychain wrapper
```

No frameworks beyond AppKit, SwiftUI (for the settings sheet), Carbon (for the hotkey), and ApplicationServices (for AX). That's it.

---

## Known sharp edges

- The ✨ popup needs **Accessibility** permission. macOS revokes it on every rebuild because ad-hoc codesigning changes the binary hash. If it gets stuck during development: `tccutil reset Accessibility com.local.promptmaker`, then re-grant.
- For web pages (Chrome / Safari) accessibility doesn't expose selected text directly — PromptMaker falls back to a silent `⌘C` that backs up and restores your clipboard. Works, but third-party clipboard managers may notice the brief blip.
- No streaming output yet — each request is a single blocking call. (PRs welcome.)
- No iCloud history sync, no Windows/Linux port, no menu localization beyond English/Chinese hints in the placeholder text.

---

## Contributing

Issues and PRs are welcome. The codebase is small (~1500 LOC of Swift) and easy to read top-to-bottom. Good first projects:

- streaming output for the result panel
- per-app backend overrides (e.g. always use Gemini in IDEs)
- packaging via a signed `.dmg`
- a Raycast/Alfred extension that fires the same pipeline

---

If PromptMaker saves you a few hundred copy-pastes a week, give the repo a ⭐. That's the whole funding model.
