# Environment Variables Setup

This document explains where to create `.env` files for the EchoShell project.

## Recommended Setup

Create `.env` files in each service directory:

### 1. `laptop-app/.env`

Create this file in the `laptop-app` directory:

```bash
OPENAI_API_KEY=sk-your-api-key-here
ELEVENLABS_API_KEY=your-elevenlabs-key-here
TUNNEL_SERVER_URL=http://localhost:8000
LAPTOP_NAME=My MacBook Pro
NODE_ENV=development
PORT=3000
```

### 2. `tunnel-server/.env`

Create this file in the `tunnel-server` directory:

```bash
PORT=8000
HOST=0.0.0.0
NODE_ENV=development
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

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `OPENAI_API_KEY` | Yes | OpenAI API key for AI agent | - |
| `ELEVENLABS_API_KEY` | No | ElevenLabs API key for TTS | - |
| `TUNNEL_SERVER_URL` | Yes | URL of the tunnel server | `http://localhost:8000` |
| `LAPTOP_NAME` | No | Name displayed for this laptop | `My Laptop` |
| `NODE_ENV` | No | Environment mode | `development` |
| `PORT` | No | Port for laptop app (if needed) | `3000` |

### tunnel-server

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `PORT` | No | Port for tunnel server | `8000` |
| `HOST` | No | Host to bind to | `0.0.0.0` |
| `NODE_ENV` | No | Environment mode | `development` |
| `PUBLIC_HOST` | **Yes** | Public hostname/IP that mobile devices can reach (e.g., your VPS IP, local network IP, or domain) | `localhost` |
| `PUBLIC_PROTOCOL` | No | Protocol for public URLs (`http` or `https`) | `http` (or `https` if PUBLIC_HOST is not localhost) |

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
