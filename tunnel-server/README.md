# Tunnel Server

WebSocket tunnel server for Voice-Controlled Terminal Management System.

## Features

- Tunnel registration and management
- WebSocket hub for bidirectional communication
- HTTP request proxying
- Authentication validation

## Setup

1. Install dependencies:
```bash
npm install
```

2. Create `.env` file:
```bash
cp .env.example .env
```

3. Run in development:
```bash
npm run dev
```

4. Build for production:
```bash
npm run build
npm start
```

## API Endpoints

### Create Tunnel
```
POST /tunnel/create
Body: { "name": "My Laptop" }
Response: { "config": { "tunnelId", "apiKey", "publicUrl", "wsUrl" } }
```

### Health Check
```
GET /health
Response: { "status": "ok", "tunnels": 0, "uptime": 123 }
```

### WebSocket Connection
```
WS /tunnel/:tunnelId?api_key=:apiKey
```

### HTTP Proxy
```
ANY /api/:tunnelId/*
Forwards to connected laptop via WebSocket
```

## Environment Variables

- `PORT` - Server port (default: 8000)
- `HOST` - Server host (default: 0.0.0.0)
- `NODE_ENV` - Environment (development/production)

## Deployment

### Option 1: VPS (DigitalOcean, AWS, etc.)
```bash
# Install Node.js 20+
npm install
npm run build

# Run with PM2
npm install -g pm2
pm2 start dist/index.js --name tunnel-server
pm2 save
```

### Option 2: Cloudflare Tunnel
```bash
brew install cloudflared
cloudflared tunnel login
cloudflared tunnel create laptop-tunnel
cloudflared tunnel route dns laptop-tunnel yourdomain.com
cloudflared tunnel run laptop-tunnel
```

## Architecture

```
[Mobile Device] → [Tunnel Server] → [Laptop]
                         ↓
                  WebSocket Hub
                         ↓
                  HTTP Proxy
```
