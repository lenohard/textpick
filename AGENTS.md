# TextPick

macOS menu bar app that captures selected text and processes it via LLM.

## Quick Start

```bash
cd TextPick
# Set AI_GATEWAY_API_KEY in .env (copy from env.example)
./run.sh
```

Then grant **Accessibility permission** when prompted (System Settings → Privacy & Security → Accessibility).

## Key Files

| File | Purpose |
|------|---------|
| `TextPick/Sources/TextPick/main.swift` | Entry point — NSApplication setup |
| `TextPick/Sources/TextPick/AppDelegate.swift` | Status bar icon, main menu, global hotkey wiring |
| `TextPick/Sources/TextPick/TextCaptureService.swift` | Selected text capture (AX API + clipboard fallback) |
| `TextPick/Sources/TextPick/PopupWindowController.swift` | Floating NSPanel positioned near mouse cursor |
| `TextPick/Sources/TextPick/PopupView.swift` | SwiftUI popup — action buttons, custom prompt, result view, history logging |
| `TextPick/Sources/TextPick/TextProcessingService.swift` | LLM API client (OpenAI-compatible) |
| `TextPick/Sources/TextPick/HistoryStore.swift` | Persistent history storage (max 100 items) |
| `TextPick/Sources/TextPick/HistoryListView.swift` | History UI component |
| `TextPick/Package.swift` | SPM config — depends on HotKey |

## Architecture

```
Global Hotkey ⌘⇧Space (HotKey lib)
        │
        ▼
TextCaptureService
  ├── Primary:  AXUIElement.kAXSelectedTextAttribute (no clipboard disruption)
  └── Fallback: simulate ⌘C → read NSPasteboard → restore clipboard
        │
        ▼
PopupWindowController (NSPanel, .floating level, .nonactivatingPanel)
  └── PopupView (SwiftUI)
        ├── Captured text preview
        ├── Action buttons: Summarize / Translate / Explain / Fix Grammar
        ├── Custom prompt input
        └── Result area (scrollable, selectable, copy button)
              │
              ▼
        TextProcessingService
          └── POST /v1/chat/completions → Vercel AI Gateway
```

## Configuration

Set in `.env` (copy `env.example`):

| Var | Default | Notes |
|-----|---------|-------|
| `AI_GATEWAY_API_KEY` | *(required)* | Vercel AI Gateway key |
| `TEXTPICK_API_URL` | `https://ai-gateway.vercel.sh/v1` | Any OpenAI-compatible endpoint |
| `TEXTPICK_MODEL` | `anthropic/claude-haiku-4.5` | Any Vercel AI Gateway model ID |

**Good model choices:**
- `anthropic/claude-haiku-4.5` — default, fast & cheap
- `anthropic/claude-sonnet-4.6` — higher quality
- `google/gemini-3-flash` — Google alternative
- `openai/gpt-5-nano` — cheapest option

## Tech Stack

- **Language:** Swift 6.2 / SwiftUI
- **Platform:** macOS 13+
- **Packages:** [HotKey](https://github.com/soffes/HotKey) (global hotkey)
- **API:** Vercel AI Gateway (`https://ai-gateway.vercel.sh/v1`) — OpenAI-compatible

## Hotkey

`⌘ + Shift + Space` — capture selected text and open popup

## Permissions Required

- **Accessibility** — to read selected text via AX API without clipboard disruption

## Features

- **Main Menu** — macOS-standard menu bar (App, Edit) for copy/paste shortcuts
- **History** — Persistent storage of past requests/results (up to 100 items), now stores full prompts and model info
- **Customizable Hotkey** — Configurable in Settings → General
- **Model Override** — Model can be set via Settings (overrides .env)
- **Test Connection** — Built-in API connectivity test in Settings → API & Model
- **Enhanced Debug Logging** — API key/URL validation and request tracing for troubleshooting

## Known Limitations / Next Steps

- [ ] Streaming responses (word-by-word output)
- [ ] Launch at login (LaunchAgent)
- [ ] Package as `.app` bundle
- [ ] Some sandboxed/Electron apps may not expose text via AX API (clipboard fallback handles these)
- [ ] Enhanced model selection with caching and search
