# Technical Specification: Voice-Controlled Terminal Management System

## 0. Project Standards and Rules

### 0.1 Mandatory English Language Policy
**CRITICAL RULE**: All project content MUST be written in English. This includes but is not limited to:
- **Source Code**: All code, comments, variable names, function names, class names, documentation strings
- **Documentation**: All markdown files, README files, technical specifications, API documentation
- **Git Commits**: All commit messages must follow Conventional Commits format and be in English
- **Code Comments**: All inline comments, block comments, and documentation comments
- **Error Messages**: All user-facing and developer-facing error messages
- **Log Messages**: All console logs, debug messages, and logging statements
- **UI Text**: All user interface text, labels, buttons, tooltips (if applicable)
- **Configuration Files**: All configuration file comments and documentation
- **Test Files**: All test descriptions, test names, and test documentation
- **API Documentation**: All endpoint descriptions, parameter documentation, response documentation

**Enforcement**: This rule is mandatory and non-negotiable. Any code, documentation, or commit that violates this rule will be rejected.

### 0.2 Conventional Commits
All git commits MUST follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

**Format**: `<type>(<scope>): <subject>`

**Types**:
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Code style changes (formatting, missing semi-colons, etc.)
- `refactor`: Code refactoring without feature changes or bug fixes
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `build`: Changes to build system or external dependencies
- `ci`: Changes to CI configuration files and scripts
- `chore`: Other changes that don't modify src or test files
- `revert`: Reverts a previous commit

**Examples**:
- `feat(ios): add QR code scanner for laptop pairing`
- `fix(terminal): resolve WebSocket reconnection issue`
- `docs(api): update endpoint documentation`
- `refactor(laptop-app): simplify key distribution logic`
- `chore: update dependencies to latest versions`

**Subject Rules**:
- Use imperative, present tense: "add" not "added" nor "adds"
- Don't capitalize the first letter
- No period (.) at the end
- Maximum 100 characters

**Body** (optional, for complex changes):
- Provide additional context about the change
- Explain the "what" and "why" vs. "how"
- Reference issue numbers if applicable

**Footer** (optional):
- Reference related issues: `Fixes #123`, `Closes #456`
- Breaking changes: `BREAKING CHANGE: description`

**Enforcement**: Commitlint is configured to automatically validate all commit messages. Commits that don't follow this format will be rejected.

## 1. Executive Summary

### 1.1 Project Overview
Distributed system for remote terminal management and execution via voice commands from mobile devices (iPhone/Apple Watch), with real-time output streaming and text-to-speech responses.

### 1.2 Key Features
- Voice command input from iPhone/Apple Watch
- Real-time terminal output mirroring on mobile and web
- Headless terminal execution via `cursor-agent` and `claude-cli`
- Multiple concurrent terminal sessions (PTY-based)
- Session context preservation across commands
- Dual output streams: raw (debugging) and filtered (TTS)
- Secure API key distribution
- Local STT/TTS processing on mobile devices
- No public IP required (tunnel-based connectivity)

### 1.3 Technology Stack
- **Server-Side (Laptop & Tunnel)**: TypeScript 5.0+, Node.js 20+, Express/Fastify, LangChain.js
- **Client-Side (Apple Devices)**: Swift 5.9+, SwiftUI (iOS 17+, watchOS 10+)
- **Infrastructure**: Cloudflare Tunnel / Custom Tunnel Server
- **AI Services**: OpenAI (GPT-4, Whisper, TTS), Anthropic Claude (via Cursor)
- **Tools**: Cursor CLI, git, system utilities

---

## 2. System Architecture

### 2.1 Component Overview

```
┌─────────────┐      ┌──────────────┐      ┌────────────────┐      ┌─────────────────┐
│ Apple Watch │ ───> │  iPhone App  │ ───> │ Tunnel Server  │ ───> │  Laptop App     │
│   (UI)      │      │ (STT/TTS)    │      │   (Proxy)      │      │ (Execution)     │
└─────────────┘      └──────────────┘      └────────────────┘      └─────────────────┘
                            │                                              │
                            │                                              │
                            └──────────────> OpenAI API <─────────────────┘
                              (ephemeral keys)           (master keys)
```

### 2.2 Core Components

#### 2.2.1 Apple Watch App
- **Purpose**: Minimal UI for voice input
- **Responsibilities**:
  - Voice recording trigger
  - Audio playback of responses
  - Minimal terminal output display
- **Technology**: WatchOS 10+, SwiftUI

#### 2.2.2 iPhone App
- **Purpose**: Main mobile interface with local media processing
- **Responsibilities**:
  - QR code scanning for laptop connection
  - Voice recording and STT processing (local with ephemeral keys)
  - Terminal mirror display with context switching
  - Claude output parsing
  - TTS synthesis (local with ephemeral keys)
  - Audio playback
  - Secure ephemeral key storage
- **Technology**: iOS 17+, SwiftUI, AVFoundation
- **Key Classes**:
  - `SecureKeyStore`: Manages ephemeral API keys
  - `LocalSTTHandler`: Speech-to-text processing
  - `LocalTTSHandler`: Text-to-speech synthesis
  - `LocalMediaManager`: Unified media coordination

#### 2.2.3 Tunnel Server (VPS)
- **Purpose**: Proxy between mobile and laptop (no public IP needed)
- **Responsibilities**:
  - Tunnel registration
  - WebSocket hub for bidirectional communication
  - HTTP/WS request routing
  - Authentication validation
- **Technology**: TypeScript, Express.js or Fastify, ws library
- **Deployment**: Any VPS (DigitalOcean, AWS, etc.) or Cloudflare Tunnel

#### 2.2.4 Laptop Application
- **Purpose**: Main execution environment
- **Responsibilities**:
  - Tunnel client (persistent WebSocket connection)
  - QR code generation for mobile pairing
  - API key management (master keys storage)
  - Ephemeral key distribution to mobile
  - Terminal session management (PTY-based)
  - LangChain.js AI agent for command routing
  - Command execution via multiple tools
  - Real-time output capture and streaming
  - Claude output parsing coordination
- **Technology**: TypeScript, Node.js 20+, Express/Fastify, LangChain.js, node-pty
- **Supported OS**: macOS (primary), Linux (secondary)

---

## 3. Detailed Requirements

### 3.1 Functional Requirements

#### FR-1: Initial Setup & Pairing
- FR-1.1: Laptop app SHALL register with tunnel server on startup
- FR-1.2: Laptop app SHALL generate QR code containing:
  - `tunnel_id`: Unique tunnel identifier
  - `tunnel_url`: Tunnel server URL
  - `key_endpoint`: Endpoint for API key requests
- FR-1.3: iPhone app SHALL scan QR code to establish connection
- FR-1.4: iPhone app SHALL request ephemeral API keys from laptop
- FR-1.5: Laptop app SHALL issue ephemeral keys with 1-hour expiration

#### FR-2: Voice Command Processing
- FR-2.1: Watch/iPhone SHALL record voice input
- FR-2.2: iPhone SHALL transcribe audio locally using Whisper API with ephemeral key
- FR-2.3: iPhone SHALL display transcribed text
- FR-2.4: iPhone SHALL send text command to laptop via tunnel API endpoint
- FR-2.5: For headless terminals, laptop SHALL execute command via PTY using `cursor-agent` or `claude-cli`
- FR-2.6: Laptop SHALL parse JSON output stream from CLI tools
- FR-2.7: Laptop SHALL extract `session_id` from CLI output and preserve it for subsequent commands
- FR-2.8: Laptop SHALL stream raw output to terminal display (web/mobile) for debugging
- FR-2.9: Laptop SHALL filter and stream only assistant messages to recording stream for TTS

#### FR-3: Terminal Management
- FR-3.1: Laptop SHALL support multiple concurrent terminal sessions (regular and headless)
- FR-3.2: Headless terminals SHALL use PTY (pseudo-terminal) for command execution
- FR-3.3: Headless terminals SHALL support `cursor_cli` (cursor-agent) and `claude_cli` (claude-cli) types
- FR-3.4: Each session SHALL maintain its own PTY instance with interactive shell
- FR-3.5: iPhone SHALL display list of active sessions with terminal type indicators
- FR-3.6: iPhone SHALL allow switching between sessions
- FR-3.7: Laptop SHALL capture terminal output in real-time via PTY data events
- FR-3.8: Output SHALL be streamed via WebSocket to mobile and web clients
- FR-3.9: Headless terminals SHALL preserve CLI `session_id` between commands for context continuity

#### FR-4: Output Processing & TTS
- FR-4.1: Laptop SHALL parse JSON output stream from headless CLI tools
- FR-4.2: Laptop SHALL extract assistant messages (type: "assistant") from JSON stream
- FR-4.3: Laptop SHALL send filtered assistant messages to RecordingStreamManager
- FR-4.4: Laptop SHALL broadcast filtered output via recording stream WebSocket
- FR-4.5: iPhone SHALL connect to recording stream WebSocket for headless terminals
- FR-4.6: iPhone SHALL receive filtered assistant text (no JSON, no system messages)
- FR-4.7: iPhone SHALL synthesize speech locally using OpenAI TTS with ephemeral key
- FR-4.8: iPhone SHALL play synthesized audio
- FR-4.9: iPhone SHALL stream audio to Apple Watch
- FR-4.10: Watch SHALL play audio through speaker

#### FR-5: Headless Terminal Execution
- FR-5.1: **Cursor Agent** SHALL execute with mandatory flags: `--output-format stream-json --print --force`
- FR-5.2: **Cursor Agent** SHALL use `--resume <session_id>` for subsequent commands to maintain context
- FR-5.3: **Claude CLI** SHALL execute with `--output-format json-stream` flag
- FR-5.4: **Claude CLI** SHALL use `--session-id <session_id>` for subsequent commands
- FR-5.5: Laptop SHALL extract `session_id` from JSON output (from `system/init` or any message with `session_id` field)
- FR-5.6: Laptop SHALL store `session_id` in session state for reuse in next command
- FR-5.7: Laptop SHALL detect command completion via `result` message type
- FR-5.8: Laptop SHALL handle command timeout (60 seconds) if completion not detected

#### FR-6: Security & Key Management
- FR-6.1: Master API keys SHALL be stored only on laptop
- FR-6.2: Laptop SHALL issue ephemeral keys with configurable expiration (default 1 hour)
- FR-6.3: Mobile SHALL store ephemeral keys in secure storage
- FR-6.4: Mobile SHALL auto-refresh keys when < 5 minutes remaining
- FR-6.5: Laptop SHALL support immediate key revocation
- FR-6.6: Laptop SHALL implement rate limiting per device (100 STT/hour, 200 TTS/hour)
- FR-6.7: Laptop SHALL log all key usage

### 3.2 Non-Functional Requirements

#### NFR-1: Performance
- NFR-1.1: Voice-to-text latency SHALL be < 2 seconds (95th percentile)
- NFR-1.2: Text-to-speech latency SHALL be < 2 seconds (95th percentile)
- NFR-1.3: Terminal output update frequency SHALL be 300ms
- NFR-1.4: Command execution response SHALL start streaming within 1 second

#### NFR-2: Reliability
- NFR-2.1: System SHALL handle network disconnections gracefully
- NFR-2.2: WebSocket SHALL auto-reconnect on connection loss
- NFR-2.3: PTY sessions SHALL be managed by the application
- NFR-2.4: Ephemeral keys SHALL be refreshed automatically

#### NFR-3: Security
- NFR-3.1: All communication SHALL use TLS/WSS
- NFR-3.2: Dangerous commands (rm -rf, mkfs, dd) SHALL be blocked or require confirmation
- NFR-3.3: API keys SHALL never be logged in plaintext
- NFR-3.4: Mobile app SHALL clear keys on logout

#### NFR-4: Usability
- NFR-4.1: QR code pairing SHALL complete in < 10 seconds
- NFR-4.2: Terminal output SHALL be readable with monospace font
- NFR-4.3: Voice commands SHALL support natural language
- NFR-4.4: Error messages SHALL be user-friendly

---

## 4. API Specifications

### 4.1 Laptop API Endpoints

#### 4.1.1 Key Management

**POST /keys/request**
```json
Request:
{
  "device_id": "iPhone-UUID-12345",
  "tunnel_id": "abc123",
  "duration_seconds": 3600,
  "permissions": ["stt", "tts"]
}

Response:
{
  "status": "success",
  "keys": {
    "openai": "sk-...",
    "elevenlabs": "..."
  },
  "expires_at": 1234567890,
  "expires_in": 3600,
  "permissions": ["stt", "tts"]
}
```

**POST /keys/refresh**
```json
Request:
{
  "device_id": "iPhone-UUID-12345",
  "tunnel_id": "abc123"
}

Response:
{
  "status": "refreshed",
  "expires_at": 1234567890,
  "expires_in": 3600
}
```

**DELETE /keys/revoke**
```
Query Params: device_id, tunnel_id

Response:
{
  "status": "revoked"
}
```

#### 4.1.2 Terminal Management

**POST /terminal/create**
```json
Request:
{
  "session_id": "dev-session",
  "working_dir": "/Users/user/projects",
  "terminal_type": "cursor_cli" | "claude_cli" | "regular" | "cursor_agent"
}

Response:
{
  "session_id": "dev-session",
  "working_dir": "/Users/user/projects",
  "terminal_type": "cursor_cli",
  "status": "created"
}
```

**Note**: For headless terminals (`cursor_cli`, `claude_cli`), the session uses PTY with interactive shell. Commands are executed via CLI tools through the shell.

**POST /terminal/{session_id}/execute**
```json
Request:
{
  "command": "List files in current directory"
}

Response:
{
  "session_id": "dev-session",
  "command": "List files in current directory",
  "output": "Headless command started"
}
```

**Note**: For headless terminals, the command is executed via PTY. The actual output is streamed via WebSocket:
- Raw output (all JSON) → `/terminal/{session_id}/stream` (for terminal display)
- Filtered output (assistant messages only) → `/recording/{session_id}/stream` (for TTS)

**GET /terminal/list**
```json
Response:
{
  "sessions": [
    {
      "session_id": "dev-session",
      "working_dir": "/Users/user/projects"
    }
  ]
}
```

**WebSocket /terminal/{session_id}/stream**
```json
Message Format:
{
  "type": "output",
  "session_id": "dev-session",
  "data": "terminal output text",
  "timestamp": 1234567890
}
```

#### 4.1.3 Headless Terminal Execution

**Headless Terminal Types**:
- `cursor_cli`: Uses `cursor-agent` CLI tool
- `claude_cli`: Uses `claude` CLI tool

**Command Execution Flow**:
1. Mobile app sends command via `POST /terminal/{session_id}/execute`
2. Laptop builds command line with proper flags:
   - `cursor-agent --output-format stream-json --print --force --resume <session_id> "prompt"`
   - `claude -p "prompt" --output-format json-stream --session-id <session_id>`
3. Command is written to PTY (shell executes it)
4. Output is captured via `pty.onData` event
5. JSON lines are parsed to extract:
   - `session_id` (stored for next command)
   - Assistant messages (sent to recording stream)
   - Result messages (indicate completion)
6. Raw output streamed to `/terminal/{session_id}/stream`
7. Filtered output streamed to `/recording/{session_id}/stream`
8. Mobile app receives filtered text and triggers TTS

### 4.2 Tunnel Server API

**POST /tunnel/create**
```json
Request:
{
  "name": "My MacBook"
}

Response:
{
  "config": {
    "tunnel_id": "abc123",
    "api_key": "secret_key",
    "public_url": "https://tunnel.example.com/api/abc123",
    "ws_url": "wss://tunnel.example.com/tunnel/abc123"
  },
  "qr_code": "data:image/png;base64,..."
}
```

**WebSocket /tunnel/{tunnel_id}/connect?api_key={key}**
```
Laptop connects here for persistent bidirectional communication
```

**ANY /api/{tunnel_id}/**
```
Proxies HTTP/WS requests to connected laptop
```

### 4.3 External APIs

#### 4.3.1 OpenAI Whisper (STT)
```
POST https://api.openai.com/v1/audio/transcriptions
Authorization: Bearer {ephemeral_key}
Content-Type: multipart/form-data

file: audio.m4a
model: whisper-1
language: en
```

#### 4.3.2 OpenAI TTS
```
POST https://api.openai.com/v1/audio/speech
Authorization: Bearer {ephemeral_key}
Content-Type: application/json

{
  "model": "tts-1-hd",
  "input": "Text to synthesize",
  "voice": "alloy",
  "speed": 1.0
}
```

---

## 5. Data Models

### 5.1 Session (TypeScript)
```typescript
interface TerminalSession {
  sessionId: string;
  pty: IPty; // node-pty instance
  workingDir: string;
  terminalType: 'regular' | 'cursor_cli' | 'claude_cli' | 'cursor_agent';
  outputBuffer: string[];
  inputBuffer: string[];
  headless?: {
    isRunning: boolean;
    cliSessionId?: string; // Session ID from CLI for context preservation
    completionTimeout?: NodeJS.Timeout;
    lastResultSeen?: boolean;
  };
  createdAt: number;
}
```

### 5.2 Ephemeral Key (TypeScript)
```typescript
interface EphemeralKey {
  openaiKey: string;
  elevenLabsKey?: string;
  expiresAt: number;
  issuedAt: number;
  deviceId: string;
  permissions: string[];
}
```

### 5.3 Tunnel Config (TypeScript)
```typescript
interface TunnelConfig {
  tunnelId: string;
  apiKey: string;
  publicUrl: string;
  wsUrl: string;
  keyEndpoint: string;
}
```

### 5.4 Swift Models (iOS/WatchOS)
```swift
struct KeyResponse: Codable {
    let status: String
    let keys: Keys
    let expiresAt: Int
    let expiresIn: Int
    let permissions: [String]
    
    struct Keys: Codable {
        let openai: String
        let elevenlabs: String?
    }
}

struct TunnelConfig: Codable {
    let tunnelId: String
    let apiKey: String
    let publicUrl: String
    let wsUrl: String
}
```

---

## 6. Implementation Plan

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] Setup tunnel server (TypeScript + Express/Fastify)
- [ ] Implement laptop tunnel client (TypeScript + WebSocket)
- [ ] Create QR code generation (TypeScript + qrcode library)
- [ ] Basic WebSocket communication
- [ ] Test laptop ↔ tunnel connection

### Phase 2: Terminal Management (Week 2-3)
- [x] Implement PTY-based terminal manager (TypeScript + node-pty)
- [x] Terminal session CRUD operations (Express routes)
- [x] Output capture and streaming (node-pty + WebSocket)
- [x] Headless terminal support (cursor-agent, claude-cli)
- [x] JSON output parsing and filtering
- [x] Session context preservation (session_id extraction and reuse)
- [x] Dual output streams (raw and filtered)
- [ ] Test multiple concurrent sessions

### Phase 3: Key Management (Week 3-4)
- [ ] Implement ephemeral key distribution (TypeScript)
- [ ] Key validation and rate limiting
- [ ] Auto-refresh mechanism
- [ ] Usage tracking and logging
- [ ] Test key lifecycle

### Phase 4: Headless Terminal Implementation (Week 4-5)
- [x] PTY-based command execution for headless terminals
- [x] cursor-agent integration with proper flags
- [x] claude-cli integration
- [x] JSON output stream parsing
- [x] Session ID extraction and preservation
- [x] Output filtering for recording stream
- [x] Command completion detection
- [x] Test command context preservation

### Phase 5: iOS App - Core (Week 5-6)
- [ ] SwiftUI project setup (Xcode)
- [ ] QR code scanner (AVFoundation)
- [ ] Secure key store (Keychain)
- [ ] WebSocket client (URLSession)
- [ ] Terminal output display (SwiftUI)
- [ ] Session switcher UI

### Phase 6: iOS App - Media (Week 6-7)
- [ ] Voice recording (AVFoundation)
- [ ] Local STT handler (OpenAI Whisper API)
- [ ] Claude output parser (Swift)
- [ ] Local TTS handler (OpenAI TTS API)
- [ ] Audio playback (AVPlayer)
- [ ] Test full voice cycle

### Phase 7: WatchOS App (Week 7-8)
- [ ] WatchOS companion app (SwiftUI)
- [ ] Voice recording button
- [ ] Audio playback
- [ ] Minimal terminal view
- [ ] iPhone ↔ Watch communication (WatchConnectivity)
- [ ] Test on physical device

### Phase 8: Integration & Testing (Week 8-9)
- [ ] End-to-end integration tests (Jest + XCTest)
- [ ] Performance optimization (Node.js profiling)
- [ ] Error handling improvements
- [ ] Security audit
- [ ] User acceptance testing

### Phase 9: Polish & Deployment (Week 9-10)
- [ ] UI/UX refinements
- [ ] Documentation (TypeDoc + Swift DocC)
- [ ] Deployment scripts (PM2/systemd)
- [ ] App Store preparation
- [ ] Beta testing (TestFlight)

---

## 7. Testing Strategy

### 7.1 Unit Tests
- **Server (TypeScript)**: Jest for key distribution, agent tools, terminal manager
- **iOS (Swift)**: XCTest for STT/TTS handlers, output parser, key store
- **Tunnel (TypeScript)**: Jest for request routing, WebSocket hub

### 7.2 Integration Tests
- Mobile ↔ Tunnel ↔ Laptop communication
- Voice command end-to-end flow
- Multi-session management
- Key refresh and revocation

### 7.3 Performance Tests
- STT/TTS latency benchmarks
- Terminal output streaming throughput
- WebSocket reconnection resilience
- Memory usage under load (Node.js profiling)

### 7.4 Security Tests
- Key expiration enforcement
- Rate limiting effectiveness
- Command injection prevention
- TLS/WSS validation

---

## 8. Deployment

### 8.1 Tunnel Server
**Option A: Cloudflare Tunnel (Recommended)**
```bash
brew install cloudflared
cloudflared tunnel login
cloudflared tunnel create laptop-tunnel
cloudflared tunnel route dns laptop-tunnel api.yourdomain.com
cloudflared tunnel run laptop-tunnel
```

**Option B: Custom VPS (TypeScript/Node.js)**
- Deploy Express/Fastify server on DigitalOcean/AWS/Hetzner
- Setup nginx reverse proxy
- Configure SSL with Let's Encrypt
- PM2 or systemd service for auto-restart

### 8.2 Laptop Application (TypeScript/Node.js)
```bash
# Install dependencies
npm install
# or
pnpm install

# Setup environment variables
export OPENAI_API_KEY="sk-..."
export ELEVENLABS_API_KEY="..."

# Build TypeScript
npm run build

# Run application
npm start

# Or as PM2 service
pm2 start dist/main.js --name laptop-app

# Or as systemd service (Linux) / LaunchAgent (macOS)
```

### 8.3 iOS Application
- Build in Xcode
- Code signing with Apple Developer account
- TestFlight for beta distribution
- App Store submission (optional)

---

## 9. Security Considerations

### 9.1 Threat Model
- **Threat**: Stolen ephemeral keys
  - **Mitigation**: 1-hour expiration, immediate revocation capability
- **Threat**: Man-in-the-middle attacks
  - **Mitigation**: TLS/WSS for all communication
- **Threat**: Malicious commands
  - **Mitigation**: Command validation, dangerous command blocking
- **Threat**: Rate limit bypass
  - **Mitigation**: Device-based rate limiting, key-based tracking

### 9.2 Best Practices
- Never log API keys in plaintext
- Use secure random for key generation
- Implement request signing (optional)
- Regular security audits
- Penetration testing before production

---

## 10. Future Enhancements

### 10.1 Planned Features
- Multi-user support (multiple mobile devices)
- Command history and favorites
- Custom voice commands (shortcuts)
- Integration with more AI providers (Anthropic direct, Gemini)
- Web interface for laptop monitoring
- Session recording and playback
- Collaborative sessions (screen sharing)

### 10.2 Advanced AI Features
- Context-aware command suggestions
- Natural language query answering
- Code review and refactoring
- Automated testing generation
- Documentation generation

---

## 11. Glossary

- **PTY**: Pseudo-terminal for terminal emulation and command execution
- **Ephemeral Key**: Temporary API key with limited lifetime
- **STT**: Speech-to-Text
- **TTS**: Text-to-Speech
- **LangFlow**: Framework for building LangChain agents
- **Cursor CLI**: AI-powered code editor command-line interface
- **Tunnel**: Proxy mechanism for accessing localhost without public IP

---

## 12. References

- [OpenAI API Documentation](https://platform.openai.com/docs)
- [LangChain.js Documentation](https://js.langchain.com/)
- [Node.js Documentation](https://nodejs.org/docs/)
- [Express.js Documentation](https://expressjs.com/)
- [node-pty Library](https://github.com/microsoft/node-pty)
- [ws WebSocket Library](https://github.com/websockets/ws)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [AVFoundation Guide](https://developer.apple.com/documentation/avfoundation/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)

---

## 13. Appendices

### Appendix A: Example Commands
```bash
# Voice command examples for headless terminals
"Clone the FastAPI repository and install dependencies"
"Create a new Python file called main.py with a hello world function"
"Show me the git status"
"List all running processes"
"What's the disk usage on this machine?"

# Headless terminal execution flow
# 1. User speaks: "Count 5 plus 10"
# 2. iPhone transcribes and sends to laptop
# 3. Laptop executes: cursor-agent --output-format stream-json --print --force "Count 5 plus 10"
# 4. Output parsed: session_id extracted, assistant message filtered
# 5. Filtered text sent to recording stream
# 6. iPhone receives text and triggers TTS
# 7. Next command uses: cursor-agent --output-format stream-json --print --force --resume <session_id> "Multiply by 2"
```

### Appendix B: Configuration Files

**Laptop .env (TypeScript)**
```bash
OPENAI_API_KEY=sk-...
ELEVENLABS_API_KEY=...
TUNNEL_SERVER_URL=https://tunnel.example.com
LAPTOP_NAME="My MacBook Pro"
NODE_ENV=production
PORT=8000
```

**Tunnel Server .env (TypeScript)**
```bash
HOST=0.0.0.0
PORT=8000
SSL_CERT=/path/to/cert.pem
SSL_KEY=/path/to/key.pem
NODE_ENV=production
```

**package.json (Laptop App)**
```json
{
  "name": "laptop-terminal-control",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/main.ts",
    "build": "tsc",
    "start": "node dist/main.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.0",
    "ws": "^8.14.0",
    "node-pty": "^1.0.0",
    "openai": "^4.20.0",
    "qrcode": "^1.5.3",
    "dotenv": "^16.3.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/express": "^4.17.0",
    "@types/ws": "^8.5.0",
    "typescript": "^5.3.0",
    "tsx": "^4.6.0",
    "jest": "^29.7.0",
    "@types/jest": "^29.5.0"
  }
}
```

**tsconfig.json**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "node",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### Appendix C: System Requirements

**Laptop**
- macOS 13+ or Linux (Ubuntu 22.04+)
- Node.js 20+ LTS
- npm/pnpm 8+
- cursor-agent or claude-cli installed and in PATH
- TypeScript 5.0+
- 8GB RAM minimum
- Active internet connection

**iPhone**
- iOS 17+
- Xcode 15+ (for development)
- Swift 5.9+
- 2GB available storage
- Microphone permissions
- Active internet connection

**Apple Watch**
- watchOS 10+
- Paired with iPhone
- Xcode 15+ (for development)

**Tunnel Server (VPS)**
- 1 vCPU
- 1GB RAM
- 10GB storage
- Ubuntu 22.04 LTS
- Node.js 20+ LTS
- nginx (for reverse proxy)

---

**Document Version**: 1.0  
**Last Updated**: 2025-01-XX  
**Author**: System Architect  
**Status**: Draft for Review