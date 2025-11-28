# Tunnel Server TTS Fix - Detailed Implementation Guide

## 🐛 Problem Statement

**TTS not working in iOS app for headless terminals**

### Root Cause Analysis

The TTS synthesis flow is broken because the tunnel server does not forward `tts_ready` events from laptop to iOS:

1. ✅ **Laptop-app** correctly generates and sends `tts_ready` event via TunnelClient
2. ❌ **Tunnel server** receives the event but **does NOT forward** it to recording stream WebSocket
3. ❌ **iOS app** never receives the event, so TTS is never synthesized
4. ❌ Recording stream WebSocket **disconnects** after 30s due to no activity

### Evidence from Logs

**Laptop-app (WORKING):**
```
🎙️ [session-xxx] Sending tts_ready with 2 assistant messages (88 chars)
🎙️🎙️🎙️ TunnelClient: Sending tts_ready event to tunnel: sessionId=session-xxx
✅✅✅ TunnelClient: Successfully sent tts_ready event (183 bytes)
```

**iOS app (NOT WORKING):**
```
🔌🔌🔌 RecordingStreamClient: WebSocket URL: wss://.../recording/session-xxx/stream
🔌🔌🔌 RecordingStreamClient: Connection state set to connecting
# ... NO MESSAGE RECEIVED ...
⚠️ Recording stream appears dead (no pong for 31s)
❌ Recording stream error: Socket is not connected
```

**Expected iOS logs (but missing):**
```
📨 RecordingStreamClient: Received raw message: {"type":"tts_ready",...}
🎙️ RecordingStreamClient: tts_ready event received with 88 chars
```

---

## 📋 Solution Overview

The tunnel server needs to:

1. **Receive** `tts_ready` events from laptop via tunnel WebSocket
2. **Broadcast** these events to ALL recording stream WebSockets for that session
3. **Maintain** proper heartbeat/pong responses for recording streams

---

## 🔧 Implementation Steps

### Step 1: Add Recording Stream Broadcasting in StreamManager

**File:** `tunnel-server/src/websocket/StreamManager.ts`

**Current state:** StreamManager manages terminal output streams but doesn't handle recording streams.

**Required changes:**

1. Add recording stream tracking:
```typescript
private recordingStreams = new Map<string, Set<WebSocket>>(); // sessionId -> Set of recording WS
```

2. Add method to register recording stream:
```typescript
/**
 * Register a recording stream WebSocket for a session
 */
registerRecordingStream(sessionId: string, ws: WebSocket): void {
  if (!this.recordingStreams.has(sessionId)) {
    this.recordingStreams.set(sessionId, new Set());
  }
  this.recordingStreams.get(sessionId)!.add(ws);
  console.log(`📝 [StreamManager] Registered recording stream for session ${sessionId}`);
}
```

3. Add method to unregister recording stream:
```typescript
/**
 * Unregister a recording stream WebSocket
 */
unregisterRecordingStream(sessionId: string, ws: WebSocket): void {
  const streams = this.recordingStreams.get(sessionId);
  if (streams) {
    streams.delete(ws);
    if (streams.size === 0) {
      this.recordingStreams.delete(sessionId);
    }
    console.log(`📝 [StreamManager] Unregistered recording stream for session ${sessionId}`);
  }
}
```

4. Add method to broadcast to recording streams:
```typescript
/**
 * Broadcast tts_ready event to all recording streams for a session
 */
broadcastToRecordingStreams(sessionId: string, event: { type: string; text: string; metadata?: any }): void {
  const streams = this.recordingStreams.get(sessionId);
  if (!streams || streams.size === 0) {
    console.warn(`⚠️ [StreamManager] No recording streams for session ${sessionId}`);
    return;
  }

  const message = JSON.stringify(event);
  let successCount = 0;
  let failCount = 0;

  streams.forEach(ws => {
    try {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message);
        successCount++;
      } else {
        console.warn(`⚠️ [StreamManager] Recording stream not open (state: ${ws.readyState})`);
        failCount++;
      }
    } catch (error) {
      console.error(`❌ [StreamManager] Error broadcasting to recording stream:`, error);
      failCount++;
    }
  });

  console.log(`📡 [StreamManager] Broadcast tts_ready to ${successCount} recording streams (${failCount} failed) for session ${sessionId}`);
}
```

---

### Step 2: Update WebSocketServer to Register Recording Streams

**File:** `tunnel-server/src/websocket/WebSocketServer.ts`

**Find method:** `handleRecordingStream(ws: WebSocket, tunnelId: string, sessionId: string, req: http.IncomingMessage)`

**Current code (approximate):**
```typescript
handleRecordingStream(ws: WebSocket, tunnelId: string, sessionId: string, req: http.IncomingMessage): void {
  // ... existing setup ...

  ws.on('close', () => {
    // ... existing cleanup ...
  });
}
```

**Add registration after WebSocket is established:**
```typescript
handleRecordingStream(ws: WebSocket, tunnelId: string, sessionId: string, req: http.IncomingMessage): void {
  console.log(`🔌 [WebSocketServer] Recording stream connected: tunnel=${tunnelId}, session=${sessionId}`);

  // ... existing heartbeat setup ...

  // **ADD THIS:** Register recording stream in StreamManager
  this.streamManager.registerRecordingStream(sessionId, ws);

  ws.on('close', () => {
    console.log(`🔌 [WebSocketServer] Recording stream closed: session=${sessionId}`);

    // **ADD THIS:** Unregister recording stream
    this.streamManager.unregisterRecordingStream(sessionId, ws);

    // ... existing cleanup ...
  });

  // **ADD THIS:** Handle errors
  ws.on('error', (error) => {
    console.error(`❌ [WebSocketServer] Recording stream error:`, error);
    this.streamManager.unregisterRecordingStream(sessionId, ws);
  });
}
```

---

### Step 3: Forward tts_ready Events in TunnelHandler

**File:** `tunnel-server/src/websocket/handlers/tunnelHandler.ts`

**Current code (approximate):**
```typescript
export function setupTunnelHandlers(
  tunnel: TunnelConnection,
  ws: WebSocket,
  streamManager: StreamManager,
  tunnelManager: TunnelManager
): void {
  ws.on('message', async (data: WebSocket.RawData) => {
    try {
      const message = JSON.parse(data.toString());
      const { type, ...payload } = message;

      switch (type) {
        case 'terminal_output':
          // ... existing terminal output handling ...
          break;

        // **ADD THIS CASE:**
        case 'tts_ready':
          handleTTSReady(payload, streamManager);
          break;

        default:
          console.warn(`⚠️ Unknown message type from tunnel: ${type}`);
      }
    } catch (error) {
      console.error('❌ Error processing tunnel message:', error);
    }
  });
}
```

**Add handler function:**
```typescript
/**
 * Handle tts_ready event from laptop and broadcast to recording streams
 */
function handleTTSReady(
  payload: { sessionId: string; text: string; metadata?: any },
  streamManager: StreamManager
): void {
  const { sessionId, text, metadata } = payload;

  console.log(`🎙️ [TunnelHandler] Received tts_ready for session ${sessionId}: ${text.length} chars`);

  // Validate payload
  if (!sessionId || !text) {
    console.error(`❌ [TunnelHandler] Invalid tts_ready payload: missing sessionId or text`);
    return;
  }

  // Create tts_ready event for iOS
  const event = {
    type: 'tts_ready',
    text: text,
    metadata: metadata || {},
    timestamp: Date.now()
  };

  // Broadcast to all recording streams for this session
  streamManager.broadcastToRecordingStreams(sessionId, event);
}
```

---

### Step 4: Verify TunnelClient Sends Correct Format

**File:** `laptop-app/src/tunnel/TunnelClient.ts`

**Find method:** `sendTTSReady` or similar

**Expected code (verify this exists):**
```typescript
sendTTSReady(sessionId: string, text: string, metadata?: any): void {
  if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
    console.error('❌ TunnelClient: Cannot send tts_ready, WebSocket not connected');
    return;
  }

  const message = {
    type: 'tts_ready',  // <-- CRITICAL: Must be exactly 'tts_ready'
    sessionId,
    text,
    metadata
  };

  const data = JSON.stringify(message);
  this.ws.send(data);

  console.log(`🎙️🎙️🎙️ TunnelClient: Sent tts_ready event (${data.length} bytes)`);
}
```

**If format is different, update to match above!**

---

### Step 5: Add Proper Heartbeat for Recording Streams

**File:** `tunnel-server/src/websocket/WebSocketServer.ts`

**In `handleRecordingStream` method:**

**Current issue:** Recording streams disconnect after 30s because no messages are sent.

**Fix:** Send periodic ping to keep connection alive:

```typescript
handleRecordingStream(ws: WebSocket, tunnelId: string, sessionId: string, req: http.IncomingMessage): void {
  // ... existing setup ...

  // **ADD THIS:** Setup ping interval
  const pingInterval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.ping();
      console.log(`💓 [WebSocketServer] Ping sent to recording stream: ${sessionId}`);
    } else {
      clearInterval(pingInterval);
    }
  }, 20000); // Ping every 20 seconds

  ws.on('pong', () => {
    console.log(`💓 [WebSocketServer] Pong received from recording stream: ${sessionId}`);
    // Update heartbeat manager
    this.heartbeatManager.recordStreamPong(ws);
  });

  ws.on('close', () => {
    clearInterval(pingInterval); // **ADD THIS**
    this.streamManager.unregisterRecordingStream(sessionId, ws);
    // ... existing cleanup ...
  });
}
```

---

## 🧪 Testing Procedure

### 1. Build and Deploy

```bash
# Build tunnel server
cd tunnel-server
npm run build

# Restart tunnel server
pm2 restart tunnel-server
# or
npm start
```

### 2. Test with Real Device

**Steps:**
1. Open iOS app
2. Create headless terminal (cursor/claude)
3. Record voice command: "Hello, what is 2 plus 2?"
4. Wait for response

**Expected iOS logs:**
```
✅ Command sent: Hello, what is 2 plus 2?
💬 WebSocket chat_message received: user - Hello...
💬 WebSocket chat_message received: assistant - 2 + 2 = 4...
📨 RecordingStreamClient: Received raw message: {"type":"tts_ready",...}
🎙️ RecordingStreamClient: tts_ready event received with XX chars
🔊 ChatTerminalView: TTS completed for text (XX chars)
```

**Expected laptop-app logs:**
```
📝 [session-xxx] Accumulated assistant message: 2 + 2 = 4...
🎙️ [session-xxx] Sending tts_ready with 1 assistant messages
🎙️🎙️🎙️ TunnelClient: Sent tts_ready event
```

**Expected tunnel-server logs:**
```
🎙️ [TunnelHandler] Received tts_ready for session session-xxx: XX chars
📡 [StreamManager] Broadcast tts_ready to 1 recording streams
```

### 3. Verify TTS Playback

**Expected behavior:**
- ✅ TTS player card appears at bottom of screen
- ✅ Audio plays automatically
- ✅ "AI Response Audio" card with play button
- ✅ `isAgentProcessing` resets to idle

---

## 📝 Code Checklist

Before testing, verify:

- [ ] `StreamManager.ts`: Added `recordingStreams` Map
- [ ] `StreamManager.ts`: Added `registerRecordingStream()` method
- [ ] `StreamManager.ts`: Added `unregisterRecordingStream()` method
- [ ] `StreamManager.ts`: Added `broadcastToRecordingStreams()` method
- [ ] `WebSocketServer.ts`: Call `registerRecordingStream()` in `handleRecordingStream()`
- [ ] `WebSocketServer.ts`: Call `unregisterRecordingStream()` on close/error
- [ ] `WebSocketServer.ts`: Added ping interval for recording streams
- [ ] `tunnelHandler.ts`: Added `case 'tts_ready'` in message handler
- [ ] `tunnelHandler.ts`: Added `handleTTSReady()` function
- [ ] `TunnelClient.ts`: Verify `sendTTSReady()` sends correct format
- [ ] All files: TypeScript compiles without errors
- [ ] Tunnel server: Builds successfully (`npm run build`)

---

## 🔍 Debugging Tips

### If TTS still doesn't work after fix:

**1. Check tunnel server logs:**
```bash
pm2 logs tunnel-server
# or
tail -f ~/.pm2/logs/tunnel-server-out.log
```

Look for:
- `🎙️ [TunnelHandler] Received tts_ready` - Did tunnel receive event?
- `📡 [StreamManager] Broadcast tts_ready to X recording streams` - Was it broadcast?
- `📝 [StreamManager] Registered recording stream` - Is iOS connected?

**2. Check iOS logs (Xcode console):**

Look for:
- `🔌🔌🔌 RecordingStreamClient: Connection state set to connecting` - WebSocket opened?
- `📨 RecordingStreamClient: Received raw message` - Did message arrive?
- `❌ RecordingStreamClient: Failed to decode TTSReadyEvent` - JSON parsing error?

**3. Check laptop-app logs:**

Look for:
- `📝 [session-xxx] Accumulated assistant message` - Messages accumulated?
- `🎙️ [session-xxx] Sending tts_ready` - Event generated?
- `✅✅✅ TunnelClient: Successfully sent tts_ready event` - Event sent?

### Common Issues:

**Issue:** Recording stream not registered
- **Cause:** iOS connected before fix deployed
- **Solution:** Restart iOS app to reconnect

**Issue:** Wrong message format
- **Cause:** TunnelClient sends different format than expected
- **Solution:** Check TunnelClient.ts and update format

**Issue:** WebSocket disconnects immediately
- **Cause:** Heartbeat not working
- **Solution:** Verify ping interval is set correctly

**Issue:** Event sent but iOS doesn't parse it
- **Cause:** JSON structure mismatch
- **Solution:** Check TTSReadyEvent struct in iOS matches event format

---

## 📂 File Structure Reference

```
tunnel-server/
├── src/
│   ├── websocket/
│   │   ├── WebSocketServer.ts          # Register recording streams, setup ping
│   │   ├── StreamManager.ts            # Add broadcasting methods
│   │   └── handlers/
│   │       └── tunnelHandler.ts        # Handle tts_ready events
│   └── ...

laptop-app/
├── src/
│   ├── tunnel/
│   │   └── TunnelClient.ts             # Verify sendTTSReady() format
│   └── ...

EchoShell/
└── EchoShell/
    └── Services/
        └── RecordingStreamClient.swift # Already handles tts_ready correctly
```

---

## 🎯 Expected Behavior After Fix

### Full Flow:

1. **User speaks** → iOS records audio
2. **Transcription** → iOS sends command to laptop
3. **Execution** → Laptop runs headless CLI (cursor/claude)
4. **Assistant response** → Laptop accumulates assistant messages
5. **Completion detected** → Laptop sends `tts_ready` event via TunnelClient
6. **Tunnel forwards** → Tunnel server broadcasts to recording stream WebSocket ✨ **NEW**
7. **iOS receives** → RecordingStreamClient receives tts_ready event ✨ **FIXED**
8. **TTS synthesis** → iOS generates audio via TTSService
9. **Playback** → iOS plays audio, shows TTS player card
10. **UI reset** → `isAgentProcessing` resets to idle

### Success Indicators:

- ✅ TTS player card appears at bottom of chat
- ✅ Audio plays automatically
- ✅ Microphone icon returns to blue (idle state)
- ✅ No "hourglass" icon stuck
- ✅ Recording stream stays connected (no timeout)

---

## 📊 Performance Considerations

### Broadcasting Overhead:

- Each `tts_ready` event is ~200-500 bytes (text + metadata)
- Typically 1 recording stream per iOS device per session
- No performance impact expected (broadcast to 1-2 clients max)

### WebSocket Keep-Alive:

- Ping interval: 20 seconds (same as terminal streams)
- Pong timeout: 30 seconds
- Minimal bandwidth: ~50 bytes/20s = 2.5 bytes/s per connection

---

## 🚀 Deployment Checklist

### Pre-deployment:

- [ ] All code changes implemented
- [ ] TypeScript compilation successful
- [ ] No linter errors
- [ ] Code reviewed

### Deployment:

- [ ] Build tunnel-server: `npm run build`
- [ ] Stop tunnel-server: `pm2 stop tunnel-server`
- [ ] Deploy new build
- [ ] Start tunnel-server: `pm2 start tunnel-server`
- [ ] Check logs: `pm2 logs tunnel-server`

### Post-deployment:

- [ ] Verify tunnel-server is running: `pm2 status`
- [ ] Test with iOS app (full TTS cycle)
- [ ] Check tunnel-server logs for tts_ready broadcasts
- [ ] Monitor for errors: `pm2 logs tunnel-server --err`

---

## 🆘 Rollback Plan

If fix causes issues:

```bash
# Rollback to previous commit
git revert HEAD
npm run build
pm2 restart tunnel-server
```

Or revert specific changes in StreamManager.ts and tunnelHandler.ts.

---

## 📞 Support

If you encounter issues during implementation:

1. Check this guide's "Debugging Tips" section
2. Review logs from all three components (iOS, laptop, tunnel)
3. Verify each checklist item is completed
4. Test with fresh iOS app restart

---

**Last Updated:** 2025-11-28
**Version:** 1.0
**Status:** Ready for Implementation
