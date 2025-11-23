# 🚀 Complete Setup Guide

## EchoShell - Voice-Controlled Terminal Management System

This guide will walk you through setting up the entire system from scratch.

---

## Prerequisites

### Hardware
- macOS laptop (or Linux - untested)
- iPhone with iOS 17+ 
- Apple Watch with watchOS 10+ (optional)

### Software
- Node.js 20+ LTS
- Xcode 15+ (for iOS development)
- npm or pnpm
- Git

---

## Part 1: iOS App Setup

### 1.1 Open Xcode Project

```bash
cd EchoShell
open EchoShell.xcodeproj
```

### 1.2 Add New Files to Xcode

**Critical Step**: All new files must be added to the Xcode project:

1. In Xcode, right-click on "EchoShell" (iOS target)
2. Select "Add Files to..."
3. Add these folders:
   - `Models/` (4 files)
   - `Services/` (6 files)
   - `Views/` (3 files)
   - `ViewModels/` (1 file)

4. **Important**: Make sure "Copy items if needed" is UNCHECKED
5. **Important**: Select target: "EchoShell" (iOS app, not Watch app)

### 1.3 Add Required Permissions

Open `Info.plist` and add:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed to scan QR codes for laptop pairing</string>

<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is needed for voice recording</string>
```

### 1.4 Build and Test

1. Select iPhone simulator or device
2. Build (⌘B)
3. Fix any import errors if they appear
4. Run (⌘R)

### 1.5 Test Standalone Mode

1. Open app on iPhone
2. Go to Settings
3. Enter OpenAI API key
4. Go to Record tab
5. Tap microphone to record
6. Should transcribe and display text

✅ **Standalone mode should work perfectly!**

---

## Part 2: Backend Setup

### 2.1 Install Tunnel Server

```bash
cd tunnel-server

# Install dependencies
npm install

# Create .env file
cp .env.example .env

# Start server
npm run dev
```

You should see:
```
✅ Tunnel Server running on port 8000
📡 WebSocket server ready
```

### 2.2 Install Laptop Application

```bash
cd ../laptop-app

# Install dependencies
npm install

# Create .env file
cp .env.example .env
```

### 2.3 Configure Laptop App

Edit `laptop-app/.env`:

```bash
# REQUIRED: Add your OpenAI API key
OPENAI_API_KEY=sk-your-actual-key-here

# Optional: Add ElevenLabs key for higher quality TTS
ELEVENLABS_API_KEY=your-key-here

# Tunnel server URL (default is fine for local testing)
TUNNEL_SERVER_URL=http://localhost:8000

# Your laptop name (will appear in QR code)
LAPTOP_NAME=My MacBook Pro

# Local port
PORT=3000
```

### 2.4 Start Laptop App

```bash
npm run dev
```

You should see:
```
🚀 Laptop Application starting...
✅ Tunnel created:
   Tunnel ID: abc123xyz...
   Public URL: http://localhost:8000/api/abc123xyz...

📱 Scan this QR code with your iPhone:

[QR CODE DISPLAYED IN TERMINAL]

✅ Laptop application ready!
📱 Waiting for mobile device connection...
```

---

## Part 3: Connect iPhone to Laptop

### 3.1 Switch to Laptop Mode

1. Open app on iPhone
2. Go to **Settings** tab
3. Find **"Operation Mode"** section
4. Tap and select **"Laptop Mode (Terminal Control)"**

### 3.2 Scan QR Code

1. Still in Settings, find **"Laptop Connection"** section
2. Tap **"Scan QR Code from Laptop"**
3. Point camera at QR code in terminal
4. Wait for scan to complete

You should see:
- iPhone: "Connected to Laptop" with green checkmark
- Laptop terminal: "🔑 Issued ephemeral keys for device: ..."

### 3.3 Verify Connection

In iPhone Settings, you should see:
- ✅ Green checkmark: "Connected to Laptop"
- Tunnel ID displayed
- "Keys expire in: 59 minutes" (or similar)

---

## Part 4: Test Voice Commands

### 4.1 Simple Terminal Command

1. Go to **Record** tab
2. Look for mode indicator at top: "Laptop Mode" with green checkmark
3. Tap microphone button
4. Say: **"list files in the current directory"**
5. Release button

**Expected flow:**
1. Recording indicator shows
2. "Transcribing..." appears
3. Text appears: "list files in the current directory"
4. Command executes on laptop
5. Result displayed in app
6. TTS speaks the result

**Laptop terminal shows:**
```
📥 POST /agent/execute
🤖 AI Agent executing: list files in the current directory
🎯 Intent: terminal_command
⚡ Executing: ls -la
✅ Command executed
```

### 4.2 Test Terminal Tab

1. Go to **Terminal** tab (new tab should appear in laptop mode)
2. Should see "No Terminal Sessions" initially
3. Tap **"Create Session"**
4. New session appears in list
5. Tap session to open
6. Real-time terminal interface appears
7. Type command: `echo "Hello from iPhone!"`
8. Press send button
9. Output appears in terminal

### 4.3 Test More Complex Commands

Try these voice commands:

**Git operations:**
- "Show git status"
- "List all branches"

**System info:**
- "Show system information"
- "What's the disk usage"

**Complex tasks:**
- "Create a new directory called test-project and change into it"

---

## Part 5: Troubleshooting

### iPhone App Won't Build

**Error**: "No such module 'SomeModule'"
- **Fix**: Make sure all new files are added to Xcode target
- Right-click file → Show File Inspector → Check "EchoShell" target

**Error**: "Cannot find type 'TunnelConfig' in scope"
- **Fix**: Add Models folder to Xcode project
- File → Add Files to "EchoShell"...

### QR Code Won't Scan

**Issue**: Camera shows but nothing happens
- **Fix**: Check camera permissions in Settings → Privacy
- Ensure QR code is clearly visible (zoom in terminal if needed)
- Try adjusting lighting

### Connection Issues

**Issue**: "Not connected to laptop" in Settings
- **Fix**: 
  1. Check tunnel server is running (`npm run dev` in tunnel-server/)
  2. Check laptop app is running (`npm run dev` in laptop-app/)
  3. Try disconnecting and rescanning QR code

**Issue**: "Error: No ephemeral keys"
- **Fix**:
  1. Disconnect from laptop (Settings → Disconnect)
  2. Rescan QR code
  3. Keys should be issued fresh

### Voice Commands Not Working

**Issue**: Transcription works but no response
- **Fix**: Check laptop app terminal for errors
- Verify OpenAI API key is valid
- Check API key has credits

**Issue**: "Error executing command"
- **Fix**: Check terminal session exists
- Create new terminal session in Terminal tab
- Try simpler command first

### Backend Errors

**Error**: "Cannot find module 'node-pty'"
- **Fix**: 
  ```bash
  cd laptop-app
  npm install
  ```

**Error**: "OPENAI_API_KEY not set"
- **Fix**: Edit `laptop-app/.env` and add your API key

**Error**: "Port 8000 already in use"
- **Fix**: Change PORT in `.env` or kill process:
  ```bash
  lsof -ti:8000 | xargs kill -9
  ```

---

## Part 6: Advanced Configuration

### Custom Tunnel Server URL

If deploying tunnel server to VPS:

1. Deploy tunnel-server to your VPS
2. Get public URL (e.g., `https://tunnel.yourdomain.com`)
3. Update `laptop-app/.env`:
   ```bash
   TUNNEL_SERVER_URL=https://tunnel.yourdomain.com
   ```
4. Restart laptop app
5. Rescan QR code on iPhone

### Multiple Laptops

Each laptop can have its own tunnel:
1. Run laptop app on each machine
2. Each generates unique QR code
3. iPhone can switch between laptops by rescanning

### Key Expiration

Keys expire after 1 hour by default. Auto-refresh happens at 5 minutes before expiry.

To manually refresh:
1. iPhone auto-refreshes in background
2. Or disconnect and reconnect

---

## Part 7: Testing Checklist

### iOS Standalone Mode ✅
- [ ] Record voice
- [ ] Transcribe successfully
- [ ] Display statistics
- [ ] Switch languages
- [ ] Sync to Watch

### iOS Laptop Mode ✅
- [ ] Switch to laptop mode in Settings
- [ ] Scan QR code successfully
- [ ] Show "Connected" status
- [ ] Display key expiration time
- [ ] Record voice command
- [ ] Execute command on laptop
- [ ] Receive and display response
- [ ] Play TTS response

### Terminal Tab ✅
- [ ] Terminal tab appears in laptop mode
- [ ] Create new session
- [ ] List sessions
- [ ] Open terminal detail
- [ ] Send commands via UI
- [ ] Receive real-time output
- [ ] Multiple sessions work

### Backend ✅
- [ ] Tunnel server starts
- [ ] Laptop app connects to tunnel
- [ ] QR code displays
- [ ] Key distribution works
- [ ] Terminal sessions created
- [ ] Commands execute
- [ ] AI agent responds
- [ ] WebSocket streaming works

---

## Part 8: Production Deployment

### iOS App

1. Archive in Xcode
2. Upload to TestFlight
3. Distribute to testers

### Tunnel Server

Deploy to VPS:

```bash
# On VPS
git clone <your-repo>
cd tunnel-server
npm install
npm run build

# Use PM2
npm install -g pm2
pm2 start dist/index.js --name tunnel-server
pm2 startup
pm2 save

# Setup nginx reverse proxy
sudo nginx -t
sudo systemctl reload nginx
```

### Laptop App

```bash
npm run build

# Run with PM2 (optional)
pm2 start dist/index.js --name laptop-app
pm2 save
```

---

## Success Criteria

✅ **You've successfully set up the system when:**

1. iPhone app builds without errors
2. Standalone mode works (voice → transcription)
3. Tunnel server runs on port 8000
4. Laptop app displays QR code
5. iPhone scans QR code and connects
6. Voice commands execute on laptop
7. Terminal tab shows real-time output
8. TTS speaks responses

---

## Next Steps

- Customize AI agent prompts in `laptop-app/src/agent/AIAgent.ts`
- Add more tools (cursor, advanced git, etc.)
- Deploy tunnel server to production
- TestFlight distribution for iOS app
- Add Watch app support (Phase 6)

---

## Support

If you encounter issues:
1. Check this troubleshooting guide
2. Review console output (both iPhone and laptop)
3. Verify all API keys are valid
4. Ensure all services are running

**Happy voice commanding! 🎤🤖💻**
