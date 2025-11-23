# Laptop Application

AI-powered terminal management application for Voice-Controlled Terminal Management System.

## Features

- Terminal session management with tmux/node-pty
- AI agent powered by LangChain + GPT-4
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
# Edit .env and add your OpenAI API key
```

3. Run in development:
```bash
npm run dev
```

## Configuration

Required environment variables:
- `OPENAI_API_KEY` - Your OpenAI API key (required)
- `ELEVENLABS_API_KEY` - ElevenLabs key (optional)
- `TUNNEL_SERVER_URL` - Tunnel server URL (default: http://localhost:8000)
- `LAPTOP_NAME` - Display name for QR code (default: "My MacBook Pro")
- `PORT` - Local server port (default: 3000)

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

### "OpenAI API error"
- Verify `OPENAI_API_KEY` is valid
- Check OpenAI account has sufficient credits

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
│   └── KeyManager.ts     # Ephemeral key distribution
├── terminal/
│   └── TerminalManager.ts # Terminal session management
└── agent/
    └── AIAgent.ts        # AI agent with LangChain
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
