# Environment Variables Setup

This document explains where to create `.env` files for the EchoShell project.

## Recommended Setup

Create `.env` files in each service directory:

### 1. `laptop-app/.env`

Create this file in the `laptop-app` directory:

```bash
# Agent Configuration (LLM for command processing)
# Option 1: OpenAI (default)
AGENT_PROVIDER=openai
AGENT_API_KEY=sk-your-agent-api-key-here
AGENT_MODEL_NAME=gpt-4o-mini  # Fastest and most cost-effective option
AGENT_TEMPERATURE=0

# Option 2: Cerebras Cloud (requires AGENT_BASE_URL)
# AGENT_PROVIDER=cerebras
# AGENT_API_KEY=your-cerebras-api-key-here
# AGENT_BASE_URL=https://api.cerebras.ai/v1  # REQUIRED for Cerebras
# AGENT_MODEL_NAME=gpt-oss-120b  # Default Cerebras model
# AGENT_TEMPERATURE=0

# STT Configuration (Speech-to-Text)
STT_PROVIDER=openai
STT_API_KEY=sk-your-stt-api-key-here
STT_MODEL=whisper-1

# TTS Configuration (Text-to-Speech)
TTS_PROVIDER=openai
TTS_API_KEY=sk-your-tts-api-key-here
TTS_MODEL=tts-1  # Faster and 50% cheaper than tts-1-hd
TTS_VOICE=alloy

# Tunnel Configuration
TUNNEL_SERVER_URL=http://localhost:8000
LAPTOP_NAME=My MacBook Pro
LAPTOP_AUTH_KEY=your-secure-auth-key-here  # Generate with: openssl rand -hex 32
TUNNEL_REGISTRATION_API_KEY=dev-key-123  # Must match tunnel server

# Optional
NODE_ENV=development
PORT=3000
```

### 2. `tunnel-server/.env`

Create this file in the `tunnel-server` directory:

**Development:**
```bash
PORT=8000
HOST=0.0.0.0
NODE_ENV=development
PUBLIC_HOST=localhost
PUBLIC_PROTOCOL=http
TUNNEL_REGISTRATION_API_KEY=dev-key-123  # For dev only - use strong key in production
```

**Production (with nginx + Let's Encrypt):**
```bash
PORT=3000
HOST=127.0.0.1
NODE_ENV=production
PUBLIC_HOST=example.com:443
PUBLIC_PROTOCOL=https
TUNNEL_REGISTRATION_API_KEY=your-secret-api-key-here  # Generate with: openssl rand -hex 32
```

**Generate API key securely:**
```bash
# Generate 256-bit random key (recommended)
openssl rand -hex 32

# Alternative: base64 encoded
openssl rand -base64 32

# Copy the output and use it as TUNNEL_REGISTRATION_API_KEY value
```

## Alternative: Root `.env` File

You can also create a single `.env` file at the project root (`/Users/roman/work/roman/echoshell/.env`) with all variables. The services will automatically load it as a fallback.

**Note:** Service-specific `.env` files take precedence over the root `.env` file.

## Quick Setup

1. Copy the example files:
   ```bash
   cp laptop-app/.env.example laptop-app/.env
   cp tunnel-server/.env.example tunnel-server/.env
   ```

2. Edit the `.env` files with your actual API keys and configuration.

3. **Important:** Add `.env` to `.gitignore` to avoid committing secrets:
   ```bash
   echo ".env" >> .gitignore
   ```

## Environment Variables Reference

### laptop-app

#### Agent Configuration (LLM)

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `AGENT_PROVIDER` | No | Provider type (`openai`, `cerebras`) | `openai` |
| `AGENT_API_KEY` | **Yes** | API key for the LLM agent | - |
| `AGENT_MODEL_NAME` | No | Model name (e.g., `gpt-4o-mini`, `gpt-4`, `gpt-oss-120b`) | `gpt-4o-mini` (OpenAI) or `gpt-oss-120b` (Cerebras) |
| `AGENT_BASE_URL` | **Yes** (Cerebras) | Base URL for providers. **Required for Cerebras**: `https://api.cerebras.ai/v1` | - |
| `AGENT_TEMPERATURE` | No | Temperature setting | `0` |

#### STT Configuration (Speech-to-Text)

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `STT_PROVIDER` | No | Provider type (`openai`, `elevenlabs`) | `openai` |
| `STT_API_KEY` | **Yes** | API key for STT provider | - |
| `STT_BASE_URL` | No | Base URL for providers | - |
| `STT_MODEL` | No | Model name (e.g., `whisper-1` for OpenAI) | `whisper-1` |

#### TTS Configuration (Text-to-Speech)

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `TTS_PROVIDER` | No | Provider type (`openai`, `elevenlabs`) | `openai` |
| `TTS_API_KEY` | **Yes** | API key for TTS provider | - |
| `TTS_BASE_URL` | No | Base URL for providers | - |
| `TTS_MODEL` | No | Model name (e.g., `tts-1`, `tts-1-hd` for OpenAI) | `tts-1` |
| `TTS_VOICE` | No | Voice name (e.g., `alloy` for OpenAI) | `alloy` |

#### General Configuration

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `TUNNEL_SERVER_URL` | Yes | URL of the tunnel server | `http://localhost:8000` |
| `LAPTOP_NAME` | No | Name displayed for this laptop | `My Laptop` |
| `LAPTOP_AUTH_KEY` | Yes | Authentication key for laptop (generate with: `openssl rand -hex 32`) | - |
| `TUNNEL_REGISTRATION_API_KEY` | Yes | Secret key for tunnel registration (must match tunnel server) | - |
| `NODE_ENV` | No | Environment mode | `development` |
| `PORT` | No | Port for laptop app (if needed) | `3000` |

**Important Notes:**
- `AGENT_API_KEY`, `STT_API_KEY`, and `TTS_API_KEY` are **completely separate** and serve different purposes
- `AGENT_API_KEY`: Used exclusively for LLM agent (command processing, intent classification)
- `STT_API_KEY`: Used exclusively for speech-to-text (Whisper, etc.)
- `TTS_API_KEY`: Used exclusively for text-to-speech (TTS, etc.)
- No fallback between these keys - they are independent

### tunnel-server

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `PORT` | No | Internal port tunnel server listens on (must match nginx `proxy_pass` if using reverse proxy) | `8000` |
| `HOST` | No | Bind address. **Use `127.0.0.1` in production** (localhost-only, not accessible from internet). `0.0.0.0` binds to all interfaces (requires firewall rules). | `0.0.0.0` |
| `NODE_ENV` | No | Environment mode | `development` |
| `PUBLIC_HOST` | **Yes** | Public hostname/IP that mobile devices can reach. Include port if needed (e.g., `example.com:443`) | `localhost` |
| `PUBLIC_PROTOCOL` | No | Protocol for public URLs (`http` or `https`). Use `https` when using SSL/TLS (nginx handles SSL termination) | `http` |
| `TUNNEL_REGISTRATION_API_KEY` | **Yes** | Secret key for tunnel registration. Generate with: `openssl rand -hex 32` | - |

**Production Configuration Example (nginx + Let's Encrypt):**
```bash
PORT=3000
HOST=127.0.0.1
NODE_ENV=production
PUBLIC_HOST=example.com:443
PUBLIC_PROTOCOL=https
TUNNEL_REGISTRATION_API_KEY=your-secret-api-key-here  # Generate with: openssl rand -hex 32
```

**Generate API key securely:**
```bash
# Generate 256-bit random key (recommended)
openssl rand -hex 32

# Alternative: base64 encoded
openssl rand -base64 32

# Copy the output and use it as TUNNEL_REGISTRATION_API_KEY value
```

**Configuration Notes:**
- When using nginx with SSL offloading, set `PUBLIC_HOST` to your domain with port (e.g., `domain.com:443`)
- Set `PUBLIC_PROTOCOL=https` since nginx handles SSL termination
- The tunnel server listens on `HOST:PORT` internally (e.g., `127.0.0.1:3000`)
- nginx proxies external HTTPS/WSS requests to the internal tunnel server
- **Security**: Use `HOST=127.0.0.1` to bind only to localhost. Configure firewall rules to block the tunnel server port (e.g., 3000) from external access. Only nginx on localhost should be able to connect. See tunnel-server README for firewall configuration details.

**Important:** Set `PUBLIC_HOST` to the IP address or hostname that your iPhone can reach:
- **Local network**: Use your laptop's local IP (e.g., `192.168.1.100`)
- **VPS/Cloud**: Use your server's public IP or domain (e.g., `tunnel.example.com`)
- **Development**: Use `localhost` only if testing on simulator

## Loading Priority

The services load environment variables in this order (later values override earlier ones):

1. System environment variables
2. Service-specific `.env` file (e.g., `laptop-app/.env`) - **highest priority**
3. Root `.env` file (e.g., `echoshell/.env`) - fallback only

**When running from root using npm scripts:**
- The root npm scripts (e.g., `npm run dev:laptop-app`) explicitly set `DOTENV_CONFIG_PATH=./.env` 
- This ensures the service-specific `.env` files are always used
- The path is resolved relative to the service directory after `cd` command

This allows you to:
- Override specific services with service-specific `.env` files
- Share common variables via root `.env` file (as fallback)
- Use system environment variables for production deployments
- Run from root directory while still using service-specific `.env` files
