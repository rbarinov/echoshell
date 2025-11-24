# 🎙️ EchoShell - Voice-Controlled Terminal Management System

An AI-powered system that lets you control your laptop's terminal using voice commands from your iPhone or Apple Watch, with real-time terminal streaming and intelligent command execution.

## 🌟 Features

### Dual Operation Modes
- **Standalone Mode**: Direct OpenAI transcription for voice-to-text
- **Laptop Mode**: Full terminal control with AI-powered command execution

### Voice Command Control
- 🎤 Natural language voice commands
- 🤖 AI agent interprets and executes commands
- 🔊 Text-to-speech responses
- 📊 Real-time statistics tracking

### Terminal Management
- 📟 Multiple concurrent terminal sessions
- 🔄 Real-time output streaming via WebSocket
- 🖥️ Terminal UI on iPhone
- ⚡ Execute commands directly or via AI agent

### Security & Privacy
- 🔐 Ephemeral API keys (1-hour expiration)
- 🛡️ Keychain storage on iOS
- 🔑 Master keys stored only on laptop
- 📱 Device-specific key distribution

### Seamless Integration
- 📲 QR code pairing for instant connection
- ⌚ Apple Watch support
- 🔄 Auto-reconnect with exponential backoff
- 🎯 Intelligent intent classification

---

## 📁 Project Structure

```
echoshell/
├── EchoShell/                      # iOS & WatchOS apps (Swift/SwiftUI)
│   ├── EchoShell/                 # iOS app
│   │   ├── Models/                # Data models (NEW)
│   │   ├── Services/              # Business logic (NEW)
│   │   ├── Views/                 # UI components (NEW)
│   │   ├── ViewModels/            # State management (NEW)
│   │   └── [Existing files modified]
│   ├── EchoShell Watch App/       # Watch app
│   └── EchoShell.xcodeproj        # Xcode project
│
├── tunnel-server/                  # Tunnel proxy server (TypeScript)
│   ├── src/
│   │   └── index.ts               # WebSocket hub & HTTP proxy
│   ├── package.json
│   └── README.md
│
├── laptop-app/                     # Laptop application (TypeScript)
│   ├── src/
│   │   ├── index.ts               # Main app
│   │   ├── tunnel/                # Tunnel client
│   │   ├── keys/                  # Key management
│   │   ├── terminal/              # Terminal sessions
│   │   └── agent/                 # AI agent
│   ├── package.json
│   └── README.md
│
└── Documentation/
    ├── SETUP_GUIDE.md             # Complete setup instructions
    ├── FINAL_IMPLEMENTATION_SUMMARY.md
    └── CLAUDE.md                  # Original spec
```

---

## 🚀 Quick Start

### 1. iOS App Setup

```bash
cd EchoShell
open EchoShell.xcodeproj

# Add new folders to Xcode target:
# - Models/, Services/, Views/, ViewModels/
# Build and run on iPhone
```

### 2. Backend Setup

```bash
# Terminal 1: Tunnel Server
cd tunnel-server
npm install
npm run dev

# Terminal 2: Laptop App
cd laptop-app
npm install
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY
npm run dev
```

### 3. Connect iPhone

1. Open app on iPhone
2. Settings → Switch to "Laptop Mode"
3. Scan QR code from laptop terminal
4. Start voice commanding!

**See [SETUP_GUIDE.md](SETUP_GUIDE.md) for detailed instructions.**

---

## 🧠 Headless CLI Sessions

Direct (voice) control on iPhone and Apple Watch now runs against _headless_ CLI sessions that stream structured JSON output:

- **`cursor_cli`** – wraps `cursor-agent --output-format stream-json --stream-partial-output`
- **`claude_cli`** – wraps `claude -p --output-format stream-json`
- Classic `regular` / `cursor_agent` sessions remain for desktop/web use but are no longer required for mobile voice loops.

Create headless sessions from the mobile/Watch UI (or via `POST /terminal/create` with `terminal_type` `cursor_cli` / `claude_cli`). The laptop app parses the streaming JSON (`assistant`, `result`, etc.) and forwards only the clean deltas to the recording stream so iOS/watchOS can TTS without brittle ANSI filtering.

### Optional CLI Overrides

```
CURSOR_HEADLESS_BIN=/usr/local/bin/cursor-agent
CURSOR_HEADLESS_EXTRA_ARGS=--force
CLAUDE_HEADLESS_BIN=/usr/local/bin/claude
CLAUDE_HEADLESS_EXTRA_ARGS=--verbose
```

Add these to `laptop-app/.env` if your binaries live outside `$PATH` or need extra flags.

---

## 💡 Usage Examples

### Simple Commands
- "List files in this directory"
- "Show git status"
- "Check system information"

### Git Operations
- "Clone the React repository"
- "Create a new branch called feature"
- "Show recent commits"

### Complex Multi-Step Tasks
- "Clone the repo and install dependencies"
- "Create a new React app in the projects folder"
- "Build and test the application"

---

## 🏗️ Architecture

```
┌─────────────┐      ┌──────────────┐      ┌────────────────┐      ┌─────────────────┐
│ Apple Watch │ ───> │  iPhone App  │ ───> │ Tunnel Server  │ ───> │  Laptop App     │
│   (Voice)   │      │ (STT/TTS)    │      │   (Proxy)      │      │ (Execution)     │
└─────────────┘      └──────────────┘      └────────────────┘      └─────────────────┘
                            │                                              │
                            │                                              │
                            └──────────────> OpenAI API <─────────────────┘
                              (ephemeral keys)           (master keys)
```

### Components

1. **iOS/WatchOS Apps** (Swift/SwiftUI)
   - Voice recording & transcription
   - QR code scanning
   - Terminal UI
   - TTS playback

2. **Tunnel Server** (TypeScript/Node.js)
   - WebSocket hub
   - HTTP proxy
   - No public IP needed

3. **Laptop Application** (TypeScript/Node.js)
   - Terminal management (node-pty)
   - AI agent (LangChain + GPT-4)
   - Key distribution
   - Real-time streaming

---

## 🔧 Technology Stack

### Frontend (iOS/WatchOS)
- Swift 5.9+
- SwiftUI
- AVFoundation (audio)
- Vision (QR scanning)
- Security (Keychain)
- WatchConnectivity

### Backend
- TypeScript 5.3+
- Node.js 20+
- Express
- WebSocket (ws)
- LangChain.js
- node-pty
- OpenAI API

---

## 📊 Implementation Status

### ✅ Completed (100%)

- **iOS App** - All features implemented
  - ✅ Dual mode support
  - ✅ QR code scanner
  - ✅ Terminal UI
  - ✅ Voice command integration
  - ✅ Secure key management
  - ✅ Real-time streaming

- **Backend Infrastructure** - Core features complete
  - ✅ Tunnel server with WebSocket
  - ✅ Laptop app with AI agent
  - ✅ Terminal management
  - ✅ Key distribution API
  - ✅ Multi-tool AI agent

### 🚧 Pending

- [ ] End-to-end integration testing
- [ ] Production deployment
- [ ] Advanced AI tools (cursor integration)
- [ ] UI polish & animations
- [ ] Comprehensive error handling
- [ ] Rate limiting

---

## 📖 Documentation

- **[SETUP_GUIDE.md](SETUP_GUIDE.md)** - Complete setup & troubleshooting
- **[FINAL_IMPLEMENTATION_SUMMARY.md](FINAL_IMPLEMENTATION_SUMMARY.md)** - Implementation details
- **[tunnel-server/README.md](tunnel-server/README.md)** - Tunnel server docs
- **[laptop-app/README.md](laptop-app/README.md)** - Laptop app docs
- **[CLAUDE.md](CLAUDE.md)** - Original technical specification

---

## 🔒 Security

- Master API keys stored only on laptop (environment variables)
- Ephemeral keys issued with 1-hour expiration
- Automatic key refresh at 5 minutes before expiry
- Keychain storage on iOS (not UserDefaults)
- Device-specific key distribution
- Immediate key revocation capability
- Rate limiting per device (planned)

---

## 🧪 Testing

### Manual Testing Checklist

**Standalone Mode:**
- [ ] Voice recording
- [ ] Transcription
- [ ] Statistics display
- [ ] Language switching

**Laptop Mode:**
- [ ] QR code pairing
- [ ] Key distribution
- [ ] Voice command execution
- [ ] TTS response
- [ ] Terminal UI
- [ ] Real-time streaming
- [ ] Session management

**AI Agent:**
- [ ] Simple commands
- [ ] Git operations
- [ ] File operations
- [ ] System queries
- [ ] Multi-step tasks

---

## 🚀 Deployment

### Development

```bash
# Tunnel Server
cd tunnel-server && npm run dev

# Laptop App
cd laptop-app && npm run dev

# iOS App
Open in Xcode and run
```

### Production

**Tunnel Server:**
```bash
# VPS deployment
npm run build
pm2 start dist/index.js --name tunnel-server

# Or use Cloudflare Tunnel
cloudflared tunnel run laptop-tunnel
```

**Laptop App:**
```bash
npm run build
pm2 start dist/index.js --name laptop-app
```

**iOS App:**
- Archive in Xcode
- Upload to TestFlight
- Distribute

---

## 📈 Metrics

- **Total Files Created**: 30+
- **Lines of Code**: ~5,000+
- **iOS Components**: 20 (models, services, views, viewmodels)
- **Backend Modules**: 4 (tunnel, keys, terminal, agent)
- **API Endpoints**: 10+

---

## 🗺️ Roadmap

### Phase 1 ✅ - Foundation (Complete)
- iOS app infrastructure
- Backend server setup
- Basic connectivity

### Phase 2 🚧 - Enhancement (In Progress)
- [ ] Advanced AI tools
- [ ] Cursor CLI integration
- [ ] More sophisticated error handling
- [ ] Performance optimization

### Phase 3 📋 - Production Ready
- [ ] Comprehensive testing suite
- [ ] CI/CD pipeline
- [ ] Monitoring & logging
- [ ] Documentation updates

### Phase 4 🎯 - Future Features
- [ ] Multi-user support
- [ ] Command history
- [ ] Custom voice shortcuts
- [ ] Web interface
- [ ] Collaborative sessions

---

## 🤝 Contributing

This is a personal project, but contributions are welcome!

1. Fork the repository
2. Create feature branch
3. Make changes
4. Test thoroughly
5. Submit pull request

---

## 📝 License

MIT License

Copyright (c) 2025 Roman Barinov (rbarinov@gmail.com)

This software has been developed by Roman Barinov in 2025.

See [LICENSE](LICENSE) file for full license text.

---

## 🙏 Acknowledgments

- OpenAI for GPT-4 and Whisper APIs
- Apple for SwiftUI and WatchOS frameworks
- LangChain for AI agent framework
- Node-pty for terminal emulation

---

## 📧 Contact

For questions or issues, please open a GitHub issue.

---

**Built with ❤️ using Swift, TypeScript, and AI**

🎤 **Speak. Execute. Repeat.** 🚀
