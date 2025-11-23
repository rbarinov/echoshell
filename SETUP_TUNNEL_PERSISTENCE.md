# Quick Setup Guide: Persistent Tunnel ID & API Key Authentication

## Overview

Your tunnel system now has:
- ✅ **Persistent Tunnel ID** stored in `~/.echoshell/state.json`
- ✅ **API Key Authentication** for secure tunnel registration

## Setup Steps

### 1. Generate API Key

```bash
openssl rand -hex 32
```

**Output example**: `a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456`

Copy this key!

---

### 2. Configure Tunnel Server

```bash
cd tunnel-server

# Add to .env file (or create if doesn't exist)
echo "TUNNEL_REGISTRATION_API_KEY=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456" >> .env
```

---

### 3. Configure Laptop App

```bash
cd ../laptop-app

# Add to .env file (use SAME key as tunnel server)
echo "TUNNEL_REGISTRATION_API_KEY=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456" >> .env
```

⚠️ **Keys MUST match exactly!**

---

### 4. Start Services

```bash
# Terminal 1: Start tunnel server
cd tunnel-server
npm start

# Output:
# 🔑 Registration API key configured
# ✅ Tunnel Server running on port 8000
```

```bash
# Terminal 2: Start laptop app
cd laptop-app
npm run dev:laptop-app

# First run:
# ✅ New tunnel created
#    Tunnel ID: a1b2c3d4e5f6
# 💾 Tunnel state saved to: ~/.echoshell/state.json
# 📱 Scan this QR code with your iPhone
```

---

### 5. Verify Persistent State

```bash
# Check state file was created
cat ~/.echoshell/state.json

# Should show:
# {
#   "tunnelId": "a1b2c3d4e5f6",
#   "apiKey": "...",
#   "publicUrl": "...",
#   "wsUrl": "...",
#   "createdAt": 1763906662425,
#   "laptopName": "My MacBook Pro"
# }
```

---

### 6. Test Persistence

```bash
# Stop laptop app (Ctrl+C)

# Restart it
npm run dev:laptop-app

# Second run:
# 📂 Loaded tunnel state from: ~/.echoshell/state.json
# 🔄 Attempting to restore tunnel: a1b2c3d4e5f6
# 🔄 Tunnel restored with existing ID
# 📱 iPhone app continues working! (no new QR code)
```

---

## What Changed

### Before
- New tunnel ID every restart
- iPhone had to re-scan QR code
- Lost tunnel after server restart

### After
- Same tunnel ID persists
- iPhone keeps working after restart
- Tunnel state saved in `~/.echoshell/state.json`

---

## Complete Environment Variables

### tunnel-server/.env

```bash
PORT=8000
HOST=0.0.0.0
PUBLIC_HOST=localhost
PUBLIC_PROTOCOL=http
TUNNEL_REGISTRATION_API_KEY=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

### laptop-app/.env

```bash
TUNNEL_SERVER_URL=http://localhost:8000
TUNNEL_REGISTRATION_API_KEY=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
OPENAI_API_KEY=sk-your-key-here
LAPTOP_NAME=My MacBook Pro
```

---

## Troubleshooting

### Error: "Invalid TUNNEL_REGISTRATION_API_KEY"

```
❌ Unauthorized: Invalid TUNNEL_REGISTRATION_API_KEY
```

**Fix**: Ensure both `.env` files have EXACTLY the same key (no extra spaces).

### Error: "TUNNEL_REGISTRATION_API_KEY is not set"

**Fix**: Add the key to your `.env` file:
```bash
echo "TUNNEL_REGISTRATION_API_KEY=$(openssl rand -hex 32)" >> .env
```

### Want to Reset Tunnel ID?

```bash
# Delete state file
rm ~/.echoshell/state.json

# Restart laptop app
npm run dev:laptop-app

# New tunnel ID will be created
# iPhone will need to re-scan QR code
```

---

## Summary

✅ **Setup complete!**
- Tunnel ID persists across restarts
- API key secures tunnel registration
- iPhone doesn't need to re-pair

Your tunnel system is now production-ready! 🚀
