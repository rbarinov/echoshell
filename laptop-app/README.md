# Laptop Application

AI-powered terminal management application for Voice-Controlled Terminal Management System.

## Features

- Terminal session management with node-pty (PTY-based)
- AI agent powered by LangChain with configurable providers (OpenAI, Cerebras Cloud, etc.)
- Configurable STT/TTS providers (OpenAI, ElevenLabs, etc.)
- Ephemeral API key distribution
- QR code generation for mobile pairing
- Real-time terminal output streaming
- 5 AI tools: git, file system, terminal, cursor, system

## Setup

1. Install dependencies:
```bash
npm install
```

2. Create `.env` file:
```bash
cp .env.example .env
# Edit .env and add your API keys (see Configuration section)
```

3. Run in development:
```bash
npm run dev
```

## Configuration

### Required Environment Variables

**Agent Configuration (LLM):**
- `AGENT_API_KEY` - **Required** API key for the LLM agent
- `AGENT_PROVIDER` - Provider type (`openai`, `cerebras`) - default: `openai`
- `AGENT_MODEL_NAME` - Model name (e.g., `gpt-4o-mini`, `gpt-4`) - default: `gpt-4o-mini`

**STT Configuration (Speech-to-Text):**
- `STT_API_KEY` - **Required** API key for STT provider
- `STT_PROVIDER` - Provider type (`openai`, `elevenlabs`) - default: `openai`
- `STT_MODEL` - Model name (e.g., `whisper-1`) - default: `whisper-1`

**TTS Configuration (Text-to-Speech):**
- `TTS_API_KEY` - **Required** API key for TTS provider
- `TTS_PROVIDER` - Provider type (`openai`, `elevenlabs`) - default: `openai`
- `TTS_MODEL` - Model name (e.g., `tts-1`, `tts-1-hd`) - default: `tts-1`

**General Configuration:**
- `TUNNEL_SERVER_URL` - Tunnel server URL (default: http://localhost:8000)
- `LAPTOP_NAME` - Display name for QR code (default: "My MacBook Pro")
- `LAPTOP_AUTH_KEY` - Authentication key for laptop (generate with: `openssl rand -hex 32`)
- `TUNNEL_REGISTRATION_API_KEY` - Secret key for tunnel registration (must match tunnel server)
- `PORT` - Local server port (default: 3000)

### Example Configuration

```bash
# Agent (LLM) - using GPT-4o-mini for speed and cost efficiency
AGENT_PROVIDER=openai
AGENT_API_KEY=sk-...
AGENT_MODEL_NAME=gpt-4o-mini

# STT (Speech-to-Text)
STT_PROVIDER=openai
STT_API_KEY=sk-...
STT_MODEL=whisper-1

# TTS (Text-to-Speech) - using tts-1 for speed and cost efficiency
TTS_PROVIDER=openai
TTS_API_KEY=sk-...
TTS_MODEL=tts-1
TTS_VOICE=alloy

# Tunnel
TUNNEL_SERVER_URL=http://localhost:8000
LAPTOP_NAME=My MacBook Pro
LAPTOP_AUTH_KEY=$(openssl rand -hex 32)
TUNNEL_REGISTRATION_API_KEY=dev-key-123
```

**Important:** `AGENT_API_KEY`, `STT_API_KEY`, and `TTS_API_KEY` are completely separate and serve different purposes. No fallback between these keys.

See [ENV_SETUP.md](../ENV_SETUP.md) for detailed configuration documentation.

## Usage

1. Start the tunnel server (in another terminal):
```bash
cd ../tunnel-server
npm run dev
```

2. Start the laptop app:
```bash
npm run dev
```

3. Scan the QR code with your iPhone app

4. Start giving voice commands!

## API Endpoints

### Key Management
- `POST /keys/request` - Issue ephemeral API keys
- `POST /keys/refresh` - Refresh existing keys
- `DELETE /keys/revoke` - Revoke keys

### Terminal Management
- `GET /terminal/list` - List active sessions
- `POST /terminal/create` - Create new session
- `POST /terminal/:id/execute` - Execute command

### AI Agent
- `POST /agent/execute` - Execute command via AI agent

## AI Agent Capabilities

The AI agent can handle:

1. **Simple Terminal Commands**
   - "list files in this directory"
   - "check npm version"
   - "show disk usage"

2. **Git Operations**
   - "clone the react repository"
   - "show git status"
   - "create a new branch called feature"

3. **File Operations**
   - "create a new file called test.js"
   - "read the package.json file"

4. **System Information**
   - "show system information"
   - "list running processes"

5. **Complex Multi-Step Tasks**
   - "clone repo and install dependencies"
   - "create a new React app"
   - "build and test the project"

## Architecture

```
[Voice Command] → [iPhone] → [Tunnel] → [Laptop App]
                                              ↓
                                         AI Agent
                                              ↓
                                    Terminal Manager
                                              ↓
                                      [Execution]
```

## Security

- Master API keys stored only on laptop
- Ephemeral keys issued with 1-hour expiration
- Device-specific key distribution
- Immediate revocation capability
- All keys stored in environment variables (never committed)

## Troubleshooting

### "Cannot connect to tunnel"
- Ensure tunnel server is running
- Check `TUNNEL_SERVER_URL` in .env

### "API key not set" errors
- Verify `AGENT_API_KEY`, `STT_API_KEY`, and `TTS_API_KEY` are all set
- Check that API keys are valid for their respective providers
- Ensure provider accounts have sufficient credits

### "Terminal session not found"
- Session may have expired
- Create a new session via mobile app

## Development

### Project Structure
```
src/
├── index.ts              # Main application
├── tunnel/
│   └── TunnelClient.ts   # Tunnel connection management
├── keys/
│   ├── KeyManager.ts     # Ephemeral key distribution
│   ├── STTProvider.ts    # STT provider abstraction
│   └── TTSProvider.ts   # TTS provider abstraction
├── terminal/
│   └── TerminalManager.ts # Terminal session management
└── agent/
    ├── AIAgent.ts        # AI agent with LangChain
    └── LLMProvider.ts   # LLM provider abstraction
```

### Testing Locally

1. Start tunnel server: `cd tunnel-server && npm run dev`
2. Start laptop app: `cd laptop-app && npm run dev`
3. Use curl to test endpoints:
```bash
# Create tunnel (simulated mobile request)
curl -X POST http://localhost:8000/tunnel/create \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Laptop"}'
```

## Production Deployment

1. Build the application:
```bash
npm run build
```

2. Run with PM2:
```bash
pm2 start dist/index.js --name laptop-app
pm2 save
```

3. Set up systemd service (Linux) or LaunchAgent (macOS) for auto-start

## License

MIT
