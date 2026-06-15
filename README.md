# Agent Dance &middot; [![Flutter](https://img.shields.io/badge/Flutter-3.5%2B-02569B?logo=flutter)](https://flutter.dev) [![Dart](https://img.shields.io/badge/Dart-3.5%2B-0175C2?logo=dart)](https://dart.dev) [![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE) [![Release](https://img.shields.io/badge/Download-APK-brightgreen?logo=android)](https://github.com/liaosiliangCodeLife/agent_dance/releases)

**A decentralized, privacy-first agent interaction network — in your pocket.**

Agent Dance is a Flutter mobile app (Android + iOS) that gives you a personal, secure entry point to your AI agents. No IM platforms. No third-party servers. Just you and your agents, end-to-end.

<p align="center">
  <img src="assets/icon.png" width="120" alt="Agent Dance icon">
</p>

---

## Why Agent Dance?

Today, interacting with AI agents (Hermes, Claude Code, OpenClaw, etc.) remotely means routing through messaging platforms — WeChat, Telegram, Discord. That comes with real problems:

| Problem | Impact |
|---------|--------|
| **Centralized dependency** | Message routing & storage controlled by platforms — can be cut off anytime |
| **Privacy risk** | Conversations pass through third-party servers |
| **Arbitrary restrictions** | API limits, bans, censorship beyond your control |

**Agent Dance cuts out the middleman.** Connect directly to your agents via your own tunnels. Your data stays on your device. Your keys stay in your keychain.

---

## Features

### Four Tabs, One App

| Tab | Purpose |
|-----|---------|
| 🧠 **Agents** | Chat with your agents — streaming Markdown, reasoning display, image & voice input |
| 🖥️ **Servers** | Manage agent nodes — add, test, monitor latency & health |
| 🔍 **Discover** | LAN agent discovery, app marketplace, help & about |
| 👤 **Me** | Profile, theme, biometric lock, data management |

### Chat Experience

- **Streaming responses** with typewriter effect and blinking cursor
- **Markdown rendering** — code blocks with syntax highlighting, tables, math
- **Reasoning process** — DeepSeek-style thinking chain, collapsible with visual distinction
- **Image input** — camera or gallery, auto-compress (≤2048px, ≤2MB), preview in chat bubble
- **Voice input** — press-and-hold recording with waveform animation, speech transcribed server-side by faster-whisper
- **Tool progress** — real-time progress bar when agent executes tools
- **Approval flow** — dangerous operation confirmation with 60s auto-approve fallback

### One Round Per Message

Every message is a fresh conversation — no history carried over. This keeps interactions lean, stateless, and private. Your chat screen shows the current exchange only.

### Screenshots

▶️ **[观看演示视频](docs/8c65a076943dacf8cd3367a186ccc8e3.mp4)**

<p align="center">
  <img src="docs/微信图片_20260615205648_66_5.jpg" width="45%" alt="Agents tab">
  &nbsp;
  <img src="docs/微信图片_20260615205648_65_5.jpg" width="45%" alt="Servers tab">
  <br>
  <img src="docs/微信图片_20260615205647_64_5.jpg" width="45%" alt="Discover tab">
  &nbsp;
  <img src="docs/微信图片_20260615205646_63_5.jpg" width="45%" alt="Me tab">
</p>

---

## Architecture

```
┌──────────────────┐          OpenAI-compatible API         ┌──────────────────┐
│   Agent Dance     │ ◀══════════════════════════════════▶ │   Hermes Agent    │
│  (Flutter App)    │      HTTP + SSE (streaming)          │  (API Server)     │
└──────────────────┘                                       └──────────────────┘
        │                                                          │
        │  LAN direct / tunnel (NPS/frp)                            │
        ▼                                                          ▼
┌──────────────────┐                                       ┌──────────────────┐
│   Local SQLite    │                                       │   LLM Backend    │
│  (drift + secure) │                                       │ (DeepSeek, etc.) │
└──────────────────┘                                       └──────────────────┘
```

**App layer**: `UI → ViewModel → Repository → Protocol/DB`

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | **Flutter** (Dart 3.5+) |
| Architecture | MVVM with `ChangeNotifier` |
| Network | `http` + manual SSE parsing |
| Local DB | SQLite via **drift** |
| Secure storage | `flutter_secure_storage` (Keychain / EncryptedSharedPreferences) |
| Markdown | `flutter_markdown` |
| Voice | `record` (M4A/AAC 16kHz mono) |
| Images | `image_picker` + `flutter_image_compress` |
| UI | Material 3 |

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.5 ([install guide](https://docs.flutter.dev/get-started/install))
- Android SDK / Xcode (for iOS)
- A running [Hermes Agent](https://hermes-agent.nousresearch.com) API Server (or any OpenAI-compatible endpoint)

### Build & Run

```bash
# Clone
git clone <repo-url> && cd agent_dance

# Install dependencies
flutter pub get

# Generate code (drift + freezed)
dart run build_runner build

# Run on connected device
flutter run

# Build Android APK (arm64 only)
flutter build apk --target-platform android-arm64
```

> **China users**: set Flutter mirrors if pub.dev is slow:
> ```powershell
> $env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
> $env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
> ```

### Connect Your Agent

1. Open App → **Servers** tab → tap **+**
2. Enter name, address (e.g. `192.168.1.100`), port (default `8642`), API key
3. Tap **Test Connection** to verify
4. Go to **Agents** tab → tap the server to start chatting

---

## Project Structure

```
agent_dance/
├── lib/
│   ├── main.dart                    # Entry point
│   ├── app.dart                     # MaterialApp + routing + theme
│   ├── config/                      # App configuration
│   ├── agents/                      # Business logic (MVVM)
│   │   ├── models/                  # Message, Session, ChatState, SseEvent
│   │   ├── database/                # SQLite (drift) — sessions + messages with reasoning
│   │   ├── repositories/            # Data layer — chat + session CRUD
│   │   └── viewmodels/              # State management (ChangeNotifier)
│   ├── protocol/                    # HTTP + SSE client
│   ├── ui/                          # Screens & widgets
│   │   ├── chatui/                  # Chat screen + message bubbles + input bar
│   │   ├── sessionui/               # Session list
│   │   └── settingui/               # Settings
│   └── utils/                       # Logger, audio service, image service
├── protocol/
│   └── api-contract.md              # API specification (OpenAI-compatible)
├── assets/
│   └── icon.png                     # App icon
├── production_describe.md           # Product vision & roadmap
└── pubspec.yaml
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [production_describe.md](./production_describe.md) | Product vision, user personas, P2P architecture vision |
| [protocol/api-contract.md](./protocol/api-contract.md) | HTTP API contract between app and Hermes Agent |

---

## Roadmap

| Phase | Focus |
|-------|-------|
| **Phase 1** ✅ | Basic chat — text, streaming, Markdown, reasoning display |
| **Phase 2** 🚧 | Multimedia — image input, voice recording + STT transcription |
| **Phase 3** | Session management — multi-session, history persistence, full-text search |
| **Phase 4** | Security — P2P encryption, biometric lock, approval flow, access control |
| **Phase 5** | Polish — LAN discovery, push notifications, multi-agent parallel chat |

---

## License

MIT © 2026

**Contact:** [liaosiliang1234@126.com](mailto:liaosiliang1234@126.com)  
**WeChat**（技术交流）：

<p align="left">
  <img src="docs/wechat-qr.jpg" width="180" alt="WeChat QR code">
</p>

---

> [中文文档](./README_zh.md)
