# Persistent Tunnel ID & API Key Authentication

## Summary

Implemented two major improvements for tunnel management:
1. ✅ **Persistent Tunnel ID** - Saved in `~/.echoshell/state.json`
2. ✅ **API Key Authentication** - Required for tunnel registration

---

## 1. Persistent Tunnel ID

### Problem
- Every time laptop app restarted, a new tunnel ID was created
- iPhone app had to re-scan QR code after server restart
- Lost connection to existing tunnel sessions

### Solution
- Save tunnel state to `~/.echoshell/state.json`
- On restart, restore existing tunnel ID
- iPhone keeps working with same configuration

### File Structure

**Location**: `~/.echoshell/state.json`

```json
{
  "tunnelId": "a1b2c3d4e5f6",
  "apiKey": "connection-api-key-here",
  "publicUrl": "http://localhost:8000/api/a1b2c3d4e5f6",
  "wsUrl": "ws://localhost:8000/tunnel/a1b2c3d4e5f6",
  "createdAt": 1763906662425,
  "laptopName": "My MacBook Pro"
}
```

### Behavior

**First Run** (no state file):
```
📡 Connecting to tunnel server
✅ New tunnel created
   Tunnel ID: a1b2c3d4e5f6
💾 Tunnel state saved to: ~/.echoshell/state.json
📱 Scan this QR code with your iPhone
```

**Subsequent Runs** (state file exists):
```
📂 Loaded tunnel state from: ~/.echoshell/state.json
   Tunnel ID: a1b2c3d4e5f6
🔄 Attempting to restore tunnel: a1b2c3d4e5f6
🔄 Tunnel restored with existing ID
   Tunnel ID: a1b2c3d4e5f6
💾 Tunnel state saved to: ~/.echoshell/state.json
📱 iPhone app continues working (no new QR code needed)
```

---

## 2. API Key Authentication

### Problem
- Anyone could register tunnels on your server
- No access control
- Security risk

### Solution
- Require `TUNNEL_REGISTRATION_API_KEY` for tunnel registration
- Must match between laptop app and tunnel server
- Returns 401 Unauthorized if key is missing or invalid

### Configuration

#### Generate Secure Key

```bash
# Generate a random 32-byte hex key
openssl rand -hex 32
```

Output example: `a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456`

#### Tunnel Server (.env)

```bash
# tunnel-server/.env
TUNNEL_REGISTRATION_API_KEY=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

#### Laptop App (.env)

```bash
# laptop-app/.env
TUNNEL_REGISTRATION_API_KEY=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

**Keys MUST match!**

### API Flow

#### Successful Registration

```http
POST /tunnel/create
X-API-Key: a1b2c3d4...
Content-Type: application/json

{
  "name": "My MacBook Pro",
  "tunnel_id": "existing-id-or-null"
}
```

**Response** (200 OK):
```json
{
  "config": {
    "tunnelId": "a1b2c3d4e5f6",
    "apiKey": "connection-key",
    "publicUrl": "http://localhost:8000/api/a1b2c3d4e5f6",
    "wsUrl": "ws://localhost:8000/tunnel/a1b2c3d4e5f6",
    "isRestored": true
  }
}
```

#### Failed Registration (No Key)

```http
POST /tunnel/create
Content-Type: application/json

{
  "name": "My MacBook Pro"
}
```

**Response** (401 Unauthorized):
```json
{
  "error": "Unauthorized",
  "message": "Valid API key required for tunnel registration"
}
```

#### Failed Registration (Wrong Key)

```http
POST /tunnel/create
X-API-Key: wrong-key
Content-Type: application/json

{
  "name": "My MacBook Pro"
}
```

**Response** (401 Unauthorized):
```json
{
  "error": "Unauthorized",
  "message": "Valid API key required for tunnel registration"
}
```

---

## Implementation Details

### New Files

**`laptop-app/src/storage/StateManager.ts`**
- `loadTunnelState()` - Load from `~/.echoshell/state.json`
- `saveTunnelState()` - Save tunnel config
- `deleteTunnelState()` - Remove state file
- `ensureStateDir()` - Create `~/.echoshell/` if needed

### Modified Files

#### Tunnel Server (`tunnel-server/src/index.ts`)

**Before**:
```typescript
app.post('/tunnel/create', (req, res) => {
  const tunnelId = crypto.randomBytes(8).toString('hex');
  // ...
});
```

**After**:
```typescript
app.post('/tunnel/create', (req, res) => {
  // Check API key
  const providedApiKey = req.headers['x-api-key'];
  if (!providedApiKey || providedApiKey !== REGISTRATION_API_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  
  // Support tunnel restoration
  const { tunnel_id } = req.body;
  const tunnelId = tunnel_id || crypto.randomBytes(8).toString('hex');
  const isRestored = !!tunnel_id;
  // ...
});
```

#### Laptop App (`laptop-app/src/index.ts`)

**Before**:
```typescript
const response = await fetch(`${tunnelUrl}/tunnel/create`, {
  method: 'POST',
  body: JSON.stringify({ name: 'My Laptop' })
});
```

**After**:
```typescript
// Load existing state
const existingState = await stateManager.loadTunnelState();

const requestBody = {
  name: 'My Laptop',
  tunnel_id: existingState?.tunnelId  // Restore if exists
};

const response = await fetch(`${tunnelUrl}/tunnel/create`, {
  method: 'POST',
  headers: {
    'X-API-Key': process.env.TUNNEL_REGISTRATION_API_KEY
  },
  body: JSON.stringify(requestBody)
});

// Save state
await stateManager.saveTunnelState(config);
```

---

## Setup Instructions

### 1. Generate API Key

```bash
openssl rand -hex 32
```

Copy the output.

### 2. Configure Tunnel Server

```bash
cd tunnel-server
echo "TUNNEL_REGISTRATION_API_KEY=<paste-your-key-here>" >> .env
```

### 3. Configure Laptop App

```bash
cd laptop-app
echo "TUNNEL_REGISTRATION_API_KEY=<paste-same-key-here>" >> .env
```

### 4. Restart Both Services

```bash
# Terminal 1: Restart tunnel server
cd tunnel-server
npm start

# Terminal 2: Restart laptop app
cd laptop-app
npm run dev:laptop-app
```

### 5. First Run

```
📡 Connecting to tunnel server
✅ New tunnel created
   Tunnel ID: a1b2c3d4e5f6
💾 Tunnel state saved to: ~/.echoshell/state.json
📱 Scan this QR code with your iPhone
```

### 6. Subsequent Runs

```
📂 Loaded tunnel state from: ~/.echoshell/state.json
🔄 Attempting to restore tunnel: a1b2c3d4e5f6
🔄 Tunnel restored with existing ID
📱 iPhone app continues working!
```

---

## Testing

### Test 1: First Time Setup

```bash
# Remove any existing state
rm -f ~/.echoshell/state.json

# Start laptop app
cd laptop-app && npm run dev:laptop-app

# Expected:
# - New tunnel ID created
# - State saved to ~/.echoshell/state.json
# - QR code displayed
```

### Test 2: Tunnel Restoration

```bash
# Stop laptop app (Ctrl+C)
# Start again
cd laptop-app && npm run dev:laptop-app

# Expected:
# - Loads existing tunnel ID
# - Restores same tunnel
# - iPhone app still works (no new QR code needed)
```

### Test 3: API Key Validation

```bash
# Wrong key in laptop-app/.env
TUNNEL_REGISTRATION_API_KEY=wrong-key

# Start laptop app
npm run dev:laptop-app

# Expected:
# ❌ Unauthorized: Invalid TUNNEL_REGISTRATION_API_KEY
# Process exits
```

### Test 4: State File Location

```bash
# Check state file
cat ~/.echoshell/state.json

# Expected:
# {
#   "tunnelId": "...",
#   "apiKey": "...",
#   ...
# }
```

### Test 5: Manual State Reset

```bash
# Delete state file
rm ~/.echoshell/state.json

# Restart laptop app
npm run dev:laptop-app

# Expected:
# - Creates new tunnel ID
# - iPhone needs to re-scan QR code
```

---

## Environment Variables

### Tunnel Server

```bash
# Required
PORT=8000
HOST=0.0.0.0
PUBLIC_HOST=localhost
PUBLIC_PROTOCOL=http
TUNNEL_REGISTRATION_API_KEY=<your-key-here>
```

### Laptop App

```bash
# Required
TUNNEL_SERVER_URL=http://localhost:8000
TUNNEL_REGISTRATION_API_KEY=<same-key-as-server>
OPENAI_API_KEY=sk-...
LAPTOP_NAME=My MacBook Pro

# Optional
ELEVENLABS_API_KEY=...
NODE_ENV=development
PORT=3000
```

---

## Troubleshooting

### Problem: 401 Unauthorized

**Error**:
```
❌ Unauthorized: Invalid TUNNEL_REGISTRATION_API_KEY
```

**Solution**:
1. Check both `.env` files have the same key
2. Restart both services
3. Ensure no extra spaces in key

### Problem: State File Not Found

**Error**:
```
📂 No existing tunnel state found
```

**Solution**:
- This is normal on first run
- State file will be created automatically
- Check: `ls -la ~/.echoshell/state.json`

### Problem: Can't Create State Directory

**Error**:
```
❌ Failed to create state directory
```

**Solution**:
```bash
# Check permissions
ls -ld ~/
# Should be writable by your user

# Manually create
mkdir -p ~/.echoshell
chmod 755 ~/.echoshell
```

### Problem: Tunnel ID Changed Unexpectedly

**Possible Causes**:
1. State file was deleted
2. State file corrupted (invalid JSON)
3. Manual deletion

**Solution**:
```bash
# Check if file exists
cat ~/.echoshell/state.json

# If corrupted, delete and restart
rm ~/.echoshell/state.json
cd laptop-app && npm run dev:laptop-app
```

---

## Security Considerations

### Registration API Key vs Connection API Key

**Two different keys**:

1. **Registration API Key** (`TUNNEL_REGISTRATION_API_KEY`)
   - Used to create/restore tunnels
   - Shared between laptop app and tunnel server
   - Long-lived (doesn't change)
   - Never exposed to mobile devices

2. **Connection API Key** (`apiKey` in response)
   - Used for WebSocket connection to tunnel
   - Generated per tunnel by server
   - Different from registration key
   - Sent to laptop app in response

### Best Practices

1. **Keep Registration Key Secret**
   - Don't commit to git
   - Use `.env` file (ignored by git)
   - Rotate periodically

2. **Generate Strong Keys**
   ```bash
   # 256 bits of randomness
   openssl rand -hex 32
   ```

3. **Separate Keys for Prod/Dev**
   ```bash
   # Development
   TUNNEL_REGISTRATION_API_KEY=dev-key-123...
   
   # Production  
   TUNNEL_REGISTRATION_API_KEY=prod-key-456...
   ```

4. **Monitor Failed Attempts**
   - Tunnel server logs all 401 errors
   - Check logs for unauthorized attempts

---

## Files Created/Modified

### Created
- `laptop-app/src/storage/StateManager.ts` - State persistence
- `TUNNEL_PERSISTENCE_AUTH.md` - This documentation

### Modified
- `tunnel-server/src/index.ts` - API key auth + tunnel restoration
- `laptop-app/src/index.ts` - State management + auth
- `tunnel-server/.env.example` - Added API key
- `laptop-app/.env.example` - Added API key

---

## Summary

✅ **Persistent Tunnel ID** - Saved in `~/.echoshell/state.json`  
✅ **API Key Authentication** - Required for registration  
✅ **Automatic Restoration** - Same tunnel ID after restart  
✅ **No Re-pairing** - iPhone works after server restart  
✅ **Secure Access** - Only authorized laptops can register  

The tunnel system is now persistent and secure! 🎉
