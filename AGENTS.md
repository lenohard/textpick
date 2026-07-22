# TextPick

macOS menu bar app that captures selected text and processes it via LLM.

## Quick Start

```bash
cd TextPick
# Set AI_GATEWAY_API_KEY in .env (copy from env.example)
./run.sh
```

Then grant **Accessibility permission** when prompted (System Settings → Privacy & Security → Accessibility).

## Install (Homebrew)

```bash
brew tap lenohard/textpick https://github.com/lenohard/textpick
brew trust lenohard/textpick
brew install --cask textpick
```

Grant **Accessibility** after first launch. If upgrading from a previous build and the hotkey stops working, reset the permission and re-grant:

```bash
tccutil reset Accessibility com.textpick.app
```

Then re-grant in **System Settings → Privacy & Security → Accessibility**.

Configure your API key in Settings.

## Build & Release

```bash
cd TextPick && ./build-app.sh          # build + install to /Applications
./release.sh 1.0.0                     # build zip, update cask sha256
./release.sh 1.0.0 --publish           # upload to GitHub Releases
```

Tag `v*` pushes trigger `.github/workflows/release.yml` to build and attach the zip automatically.

## Key Files

| File | Purpose |
|------|---------|
| `TextPick/Sources/TextPick/main.swift` | Entry point — NSApplication setup |
| `TextPick/Sources/TextPick/AppDelegate.swift` | Status bar icon, main menu, global hotkey wiring |
| `TextPick/Sources/TextPick/TextCaptureService.swift` | Selected text capture (AX API + clipboard fallback) |
| `TextPick/Sources/TextPick/PopupWindowController.swift` | Floating NSPanel positioned near mouse cursor |
| `TextPick/Sources/TextPick/PopupView.swift` | SwiftUI popup — action buttons, follow-up question input, Markdown/plain result rendering, history logging, multi-turn message chain |
| `TextPick/Sources/TextPick/TextProcessingService.swift` | LLM API client (OpenAI-compatible) + local model metadata for pricing/capabilities/context |
| `TextPick/Sources/TextPick/HistoryStore.swift` | Persistent history storage (max 100 items) |
| `TextPick/Sources/TextPick/HistoryListView.swift` | History UI component |
| `TextPick/Sources/TextPick/ActionsStore.swift` | Text & vision action definitions + CRUD + persistence |
| `TextPick/Sources/TextPick/SettingsView.swift` | Settings UI, action editors, API config, model browser/selection, hotkey UI |
| `TextPick/Package.swift` | SPM config — depends on HotKey and MarkdownUI |

## Architecture

```
Global Hotkey ⌘⇧Space (HotKey lib)
        │
        ▼
TextCaptureService
  ├── Primary:  AXUIElement.kAXSelectedTextAttribute (no clipboard disruption)
  └── Fallback: simulate ⌘C → read NSPasteboard → restore clipboard + image
        │
        ▼
PopupWindowController (NSPanel, .floating level, .nonactivatingPanel)
  └── PopupView (SwiftUI)
        ├── Mode: text OR image (clipboard screenshot)
        ├── Text: Action buttons (Format/Explain/Fix/Answer/Translate)
        ├── Image: Vision action buttons (OCR/Describe/Ask/Translate/Summarize)
        ├── Follow-up question input (multi-turn, appends to message chain)
        └── Result area (scrollable, selectable, copy, show-in-finder)
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
- **Markdown Result Rendering** — Result panel supports Markdown rendering, with plain text fallback path still in code
- **Model Browser** — Settings → API & Model includes searchable/filterable model list for browsing metadata, not only direct selection
- **Separate Text/Vision Model Selection** — Text model and vision model have independent selection areas; vision model can fall back to text model when empty
- **Model Metadata Display** — Model list shows model ID, provider, vision/thinking badges, pricing, context window, max output, and supports copying model ID
- **Vision Actions** — OCR, describe, translate, summarize images from clipboard. Each vision action is configurable: prompt, icon, enabled state.
- **Save Result to File** — Vision actions can auto-save LLM result to disk. Configurable: save directory (default `~/Pictures/TextPick`), filename format (description / timestamp / timestamp+description). After save, "Show in Finder" button appears.
- **Test Connection** — Built-in API connectivity test in Settings → API & Model
- **Settings Persistence Fix** — Custom `Decodable` init for `TextAction` uses `decodeIfPresent` to tolerate missing new fields in old saved data (backward compat)
- **Follow-up questions & direct ask** — The popup keeps a `messages: [[String: Any]]` chain per session. Clicking an action button resets the chain. A follow-up appends a user turn, re-sends the full chain, then appends the assistant turn (multi-turn, LLM sees the whole history). Vision is auto-detected by any user turn whose content is a `[[String:Any]]` content-part array, which is what picks the vision model. If no action has been run, the follow-up field still works — it builds a default user message from the captured text (`背景：.../问题：...`) or the image + question, so the user can ask without first picking an action.
- **Prompt template** — `PromptTemplate.render` only substitutes `{{text}}`. If the template doesn't contain it, the captured text is appended.

## Gotchas

- **Accessibility permission reset** — use `tccutil reset Accessibility com.textpick.app` (bundle ID). Never `tccutil reset Accessibility` without bundle ID — it resets ALL apps.
- **NSPanel close button** — `.nonactivatingPanel` style can make the built-in close button unresponsive during streaming/processing. Always add an explicit close button (e.g. `xmark.circle.fill`) in the SwiftUI header that calls `onClose` directly.
- **Popup traffic lights** — drop `.closable` from panel style mask; also hide `standardWindowButton(.close/miniaturize/zoom)` since titled panels still show them.
- **Click-outside dismiss** — global monitor alone misses same-app clicks (e.g. Settings). Add a local monitor too; close popup explicitly when opening Settings (`Cmd+,`).
- **Message chain reset on action switch** — When the user clicks a different action button mid-conversation, reset `messages` so the new system prompt doesn't get combined with stale turns. Don't append; rebuild from scratch.
- **Plain `c` key copy shortcut** — The popup registers a local key monitor that treats bare `c` (no modifiers) as "copy the current result". It must skip when the first responder is an `NSText` (e.g. the follow-up TextField), otherwise typing `c` in the field gets swallowed. Also gated on `contentMode == .result && !result.isEmpty`.

## Known Limitations / Next Steps

- [ ] Some sandboxed/Electron apps may not expose text via AX API (clipboard fallback handles these)
- [ ] Replace hardcoded model metadata with provider/gateway metadata when available
- [ ] Code signing + notarization for public distribution (currently ad-hoc signed)
