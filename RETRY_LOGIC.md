# Laptop App Retry Logic

## Overview

The laptop application now includes robust retry logic to handle tunnel server unavailability gracefully. It will automatically retry connecting to the tunnel server with exponential backoff.

## Retry Strategy

### Initial Connection

When you start the laptop app (`npm run dev:laptop-app`), it attempts to connect to the tunnel server.

**If tunnel server is not running:**

```
🚀 Laptop Application starting...
📡 Connecting to tunnel server: http://localhost:8000
❌ Failed to connect to tunnel server
   Error: fetch failed

💡 Possible reasons:
   1. Tunnel server is not running
   2. Incorrect TUNNEL_SERVER_URL in .env
   3. Network connectivity issues

🔧 To start tunnel server:
   cd tunnel-server && npm start

⏳ Retrying in 1s... (1/10)
⏳ Retrying in 2s... (2/10)
⏳ Retrying in 4s... (3/10)
⏳ Retrying in 8s... (4/10)
...
```

### Exponential Backoff

- **Attempt 1**: Wait 1 second
- **Attempt 2**: Wait 2 seconds
- **Attempt 3**: Wait 4 seconds
- **Attempt 4**: Wait 8 seconds
- **Attempt 5**: Wait 16 seconds
- **Attempt 6**: Wait 30 seconds (capped)
- **Attempt 7-10**: Wait 30 seconds each

**Maximum wait time**: 30 seconds  
**Maximum attempts**: 10

### After Successful Connection

Once connected, if the tunnel WebSocket disconnects:

- TunnelClient automatically reconnects
- **No maximum attempts** - keeps trying forever
- Same exponential backoff (1s → 2s → 4s → ... → 30s max)
- Continues until connection is restored

## Usage Scenarios

### Scenario 1: Start Laptop App Before Tunnel Server

```bash
# Terminal 1: Start laptop app first
cd laptop-app
npm run dev:laptop-app

# Output:
# 🚀 Laptop Application starting...
# ❌ Failed to connect to tunnel server
# ⏳ Retrying in 1s... (1/10)
```

```bash
# Terminal 2: Start tunnel server
cd tunnel-server
npm start

# Output in Terminal 1:
# ✅ Tunnel created
# 📱 Scan this QR code with your iPhone...
```

**Result**: Laptop app automatically connects when tunnel server starts!

### Scenario 2: Tunnel Server Crashes During Operation

```bash
# Tunnel server is running, laptop app is connected
# Kill tunnel server (Ctrl+C)
```

**Laptop app output:**
```
📡 Tunnel disconnected
🔄 Reconnecting to tunnel in 2s (attempt 1)
🔌 Attempting to reconnect...
❌ Reconnection failed: connect ECONNREFUSED
🔄 Reconnecting to tunnel in 4s (attempt 2)
...
```

**Restart tunnel server:**
```bash
cd tunnel-server
npm start
```

**Result**: Laptop app automatically reconnects!

### Scenario 3: Network Interruption

If network goes down temporarily:
- Laptop app keeps retrying (forever)
- When network comes back, automatically reconnects
- No manual intervention needed

## Configuration

### Environment Variables

**laptop-app/.env**:
```bash
# Required: Tunnel server URL
TUNNEL_SERVER_URL=http://localhost:8000

# Optional: Laptop name shown in QR code
LAPTOP_NAME="My MacBook Pro"

# Required: API keys
OPENAI_API_KEY=sk-...
ELEVENLABS_API_KEY=...
```

### Retry Parameters

**Initial connection** (in `laptop-app/src/index.ts`):
```typescript
const maxReconnectAttempts = 10;  // Change this to retry more/less
```

**WebSocket reconnection** (in `laptop-app/src/tunnel/TunnelClient.ts`):
```typescript
private maxReconnectAttempts = Infinity;  // Retry forever
```

### Backoff Calculation

```typescript
const delay = Math.min(1000 * Math.pow(2, attempt - 1), 30000);
```

- `1000 * 2^0 = 1000ms` (1s)
- `1000 * 2^1 = 2000ms` (2s)
- `1000 * 2^2 = 4000ms` (4s)
- `1000 * 2^3 = 8000ms` (8s)
- `1000 * 2^4 = 16000ms` (16s)
- `1000 * 2^5 = 32000ms` → capped at 30000ms (30s)

## Error Messages

### Connection Refused
```
❌ Failed to connect to tunnel server
   Error: fetch failed
```

**Solution**: Start tunnel server

### Invalid URL
```
❌ TUNNEL_SERVER_URL is not set in environment variables
💡 Please set TUNNEL_SERVER_URL in laptop-app/.env or root .env
```

**Solution**: Add `TUNNEL_SERVER_URL` to `.env` file

### Max Attempts Reached
```
❌ Failed to connect after 10 attempts
   Please ensure tunnel server is running and try again

💡 Run this command in a separate terminal:
   cd tunnel-server && npm start
```

**Solution**: Manually start tunnel server and restart laptop app

## Diagnostic Output

### On Startup

```
🚀 Laptop Application starting...
🎯 Laptop application starting...
📋 Loading configuration from environment variables...
   Tunnel Server: http://localhost:8000
   OpenAI API Key: sk-proj-...
   Laptop Name: My MacBook Pro

📡 Connecting to tunnel server: http://localhost:8000
```

### On Successful Connection

```
✅ Tunnel created:
   Tunnel ID: abc123def456
   Public URL: http://localhost:8000/api/abc123def456

📱 Scan this QR code with your iPhone:

[QR CODE HERE]

📡 Connecting to tunnel: wss://localhost:8000/tunnel/abc123def456?api_key=...
✅ Tunnel connected
✅ Laptop application ready!
📱 Waiting for mobile device connection...
💡 The application will continue running and retry if tunnel server disconnects
```

## Troubleshooting

### Problem: Laptop app keeps retrying but never connects

**Check tunnel server status:**
```bash
curl http://localhost:8000/health
```

**Expected response:**
```json
{"status":"ok","tunnels":0,"uptime":123.45}
```

**If connection refused:**
- Tunnel server is not running
- Wrong URL in `TUNNEL_SERVER_URL`
- Firewall blocking connection

### Problem: Tunnel server is running but laptop app can't connect

**Check URL format:**
```bash
# Correct formats:
TUNNEL_SERVER_URL=http://localhost:8000
TUNNEL_SERVER_URL=https://tunnel.example.com

# Incorrect formats:
TUNNEL_SERVER_URL=localhost:8000  # Missing protocol
TUNNEL_SERVER_URL=http://localhost:8000/  # Trailing slash
```

### Problem: "Failed to connect after 10 attempts"

**Options:**
1. Start tunnel server and restart laptop app
2. Increase max attempts in code
3. Check logs for specific error messages

## Best Practices

### Development

1. **Start tunnel server first** (recommended):
   ```bash
   cd tunnel-server && npm start
   ```

2. **Then start laptop app**:
   ```bash
   cd laptop-app && npm run dev:laptop-app
   ```

3. **Or start laptop app first** - it will wait and retry

### Production

1. Use process manager (PM2, systemd) for auto-restart
2. Configure tunnel server as a service
3. Set up health monitoring
4. Use proper logging

### Environment Setup

```bash
# Root .env (shared defaults)
TUNNEL_SERVER_URL=http://localhost:8000
OPENAI_API_KEY=sk-...
ELEVENLABS_API_KEY=...

# laptop-app/.env (overrides)
LAPTOP_NAME="My MacBook Pro"

# tunnel-server/.env (overrides)
PUBLIC_HOST=localhost
PORT=8000
```

## Related Files

- `laptop-app/src/index.ts` - Initial connection retry logic
- `laptop-app/src/tunnel/TunnelClient.ts` - WebSocket reconnection logic
- `tunnel-server/src/index.ts` - Tunnel server health endpoint

## Summary

✅ **Automatic retries** - No manual intervention needed  
✅ **Exponential backoff** - Reduces server load  
✅ **Infinite reconnection** - Handles temporary outages  
✅ **Helpful error messages** - Easy troubleshooting  
✅ **Configurable** - Adjust retry parameters as needed  

The laptop app is now **resilient to tunnel server unavailability** and will automatically recover when the tunnel server becomes available!
