# Tunnel Server

WebSocket tunnel server for Voice-Controlled Terminal Management System.

## Features

- Tunnel registration and management
- WebSocket hub for bidirectional communication
- HTTP request proxying
- Authentication validation

## Installation

### Install from GitHub Packages

#### Configure .npmrc for GitHub Packages

The `.npmrc` file tells npm where to find the package and how to authenticate. You can configure it globally (for all projects) or per-project.

**Global Configuration (Recommended):**

Create or edit `~/.npmrc`:
```bash
# Add GitHub Packages registry for @rbarinov scope
@rbarinov:registry=https://npm.pkg.github.com

# Add authentication token
//npm.pkg.github.com/:_authToken=YOUR_GITHUB_TOKEN
```

**Project-Specific Configuration:**

Create `.npmrc` in your project root:
```bash
@rbarinov:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=YOUR_GITHUB_TOKEN
```

**Creating a GitHub Personal Access Token:**

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a name (e.g., "npm-packages")
4. Select scopes: `read:packages` (minimum required)
5. Generate token and copy it
6. Replace `YOUR_GITHUB_TOKEN` in your `.npmrc` file

**Verify Configuration:**
```bash
# Check your npm configuration
npm config list

# Test installation
npm install @rbarinov/tunnel-server
```

**Security Note:** Never commit `.npmrc` files with tokens to version control. Add `.npmrc` to your `.gitignore` if it contains tokens.

### Development Setup

1. Clone the repository:
```bash
git clone https://github.com/rbarinov/echoshell.git
cd echoshell/tunnel-server
```

2. Install dependencies:
```bash
npm install
```

3. Create `.env` file:
```bash
cp .env.example .env
```

4. Run in development:
```bash
npm run dev
```

5. Build for production:
```bash
npm run build
npm start
```

## Usage

### As an npm package

```javascript
import tunnelServer from '@rbarinov/tunnel-server';

// The server starts automatically when imported
// Configure via environment variables
```

### As a standalone application

```bash
# Generate a secure API key first
export TUNNEL_REGISTRATION_API_KEY=$(openssl rand -hex 32)

# Set required environment variables
export PORT=8000
export PUBLIC_HOST=your-domain.com
export PUBLIC_PROTOCOL=https

# Start the server
npm start
```

**Note:** Generate the API key securely using:
```bash
# Generate 256-bit random key (recommended)
openssl rand -hex 32

# Or base64 encoded (alternative)
openssl rand -base64 32
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

- `TUNNEL_REGISTRATION_API_KEY` - **Required** - API key for tunnel registration
  - Generate securely: `openssl rand -hex 32` (produces 256-bit random key)
  - Alternative: `openssl rand -base64 32` (base64 encoded, 256 bits)
  - Never use weak or predictable keys
- `PORT` - Server port (default: 8000) - **Must match the port your server is actually running on**
- `HOST` - Server bind address (default: 0.0.0.0)
- `PUBLIC_HOST` - Public hostname for tunnel URLs (default: localhost)
  - If using a reverse proxy, set this to your domain (e.g., `example.com`)
  - If the hostname already includes a port (e.g., `host:3000`), it will be used as-is
- `PUBLIC_PROTOCOL` - Protocol for public URLs (default: `http`)
  - Set to `https` **only if** SSL/TLS is properly configured (certificate, reverse proxy with SSL termination, etc.)
  - **Important**: If you set this to `https` without SSL configured, WebSocket connections will fail with SSL errors
- `NODE_ENV` - Environment (development/production)

### Common Configuration Examples

**Production with nginx reverse proxy (SSL offloading via Let's Encrypt):**
```bash
PORT=3000
HOST=127.0.0.1
NODE_ENV=production
PUBLIC_HOST=example.com:443  # Domain with port (nginx handles SSL termination)
PUBLIC_PROTOCOL=https
TUNNEL_REGISTRATION_API_KEY=your-secret-api-key-here  # Generate with: openssl rand -hex 32
```

**Generate API key securely:**
```bash
# Generate 256-bit random key (recommended)
openssl rand -hex 32

# Copy the output and use it as TUNNEL_REGISTRATION_API_KEY value
```

**With nginx reverse proxy (SSL termination, no port in PUBLIC_HOST):**
```bash
PORT=3000  # Internal port tunnel server listens on
PUBLIC_HOST=example.com  # External domain (no port)
PUBLIC_PROTOCOL=https  # nginx handles SSL, so use https
```

**Direct server (no SSL):**
```bash
PORT=3000
PUBLIC_HOST=example.com
PUBLIC_PROTOCOL=http
```

**Local development:**
```bash
PORT=8000
HOST=0.0.0.0
PUBLIC_HOST=localhost
PUBLIC_PROTOCOL=http
NODE_ENV=development
TUNNEL_REGISTRATION_API_KEY=dev-key-123  # For dev only - use strong key in production: openssl rand -hex 32
```

### nginx Configuration for WebSocket Support

When using nginx as a reverse proxy with SSL, you need to configure it to proxy WebSocket connections. Here's an example configuration:

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # WebSocket upgrade headers
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    # Proxy all requests to tunnel server
    location / {
        proxy_pass http://localhost:3000;  # Internal port
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        
        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts for long-lived WebSocket connections
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

**Important Notes:**
- The tunnel server's `PORT` should match the internal port in nginx's `proxy_pass` (e.g., `3000`)
- `PUBLIC_HOST` should be your domain without port (e.g., `example.com`)
- `PUBLIC_PROTOCOL` should be `https` since nginx handles SSL
- The public URLs will be generated as `https://example.com/...` and `wss://example.com/...` (no port numbers)
- **Security**: Configure firewall rules to block direct access to the tunnel server port (3000) from the internet. Only nginx on localhost should be able to connect. See firewall configuration in deployment section.

## Deployment

### Option 1: systemd Service (Linux)

This is the recommended method for production deployments on Linux servers.

#### 1. Install the Package

**Global Installation:**
```bash
# Configure .npmrc (see Installation section above)
npm install -g @rbarinov/tunnel-server

# Find the installation path (use this in systemd service)
npm list -g @rbarinov/tunnel-server
# Or check: npm root -g
```

**Local Installation (Recommended for systemd):**
```bash
# Create application directory
sudo mkdir -p /opt/tunnel-server
cd /opt/tunnel-server

# Configure .npmrc in this directory or use global config
npm install @rbarinov/tunnel-server
```

#### 2. Create Environment File

Create `/etc/tunnel-server/.env`:
```bash
sudo mkdir -p /etc/tunnel-server
sudo nano /etc/tunnel-server/.env
```

Add your configuration (example with nginx + Let's Encrypt):
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

# Copy the output and paste it as the TUNNEL_REGISTRATION_API_KEY value
```

**Configuration Notes:**
- `PORT`: Internal port the tunnel server listens on (must match nginx `proxy_pass`)
- `HOST`: Bind address - **Use `127.0.0.1` for security** (localhost-only, not accessible from internet). Only nginx on the same host can connect.
- `PUBLIC_HOST`: Your public domain with port (e.g., `example.com:443`)
- `PUBLIC_PROTOCOL`: `https` when using SSL/TLS (nginx handles SSL termination)
- `TUNNEL_REGISTRATION_API_KEY`: Secret key for tunnel registration
  - **Generate securely**: `openssl rand -hex 32` (256-bit random key)
  - Alternative: `openssl rand -base64 32`
  - Never use weak or predictable keys in production

**Security Note:** Setting `HOST=127.0.0.1` ensures the tunnel server only listens on localhost and is not directly accessible from the internet. However, you should still configure firewall rules to explicitly block the tunnel server port from external access (see firewall configuration below).

Set proper permissions:
```bash
sudo chmod 600 /etc/tunnel-server/.env
sudo chown root:root /etc/tunnel-server/.env
```

#### 3. Create systemd Service File

Create `/etc/systemd/system/tunnel-server.service`:
```bash
sudo nano /etc/systemd/system/tunnel-server.service
```

Add the following content (adjust paths as needed):

**For global installation:**
```ini
[Unit]
Description=Tunnel Server for Voice-Controlled Terminal Management
After=network.target

[Service]
Type=simple
User=tunnel-server
Group=tunnel-server
WorkingDirectory=/opt/tunnel-server
Environment="NODE_ENV=production"
EnvironmentFile=/etc/tunnel-server/.env
ExecStart=/usr/bin/node /usr/lib/node_modules/@rbarinov/tunnel-server/dist/index.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tunnel-server

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/tunnel-server

[Install]
WantedBy=multi-user.target
```

**For local installation:**
```ini
[Unit]
Description=Tunnel Server for Voice-Controlled Terminal Management
After=network.target

[Service]
Type=simple
User=tunnel-server
Group=tunnel-server
WorkingDirectory=/opt/tunnel-server
Environment="NODE_ENV=production"
EnvironmentFile=/etc/tunnel-server/.env
ExecStart=/usr/bin/node /opt/tunnel-server/node_modules/@rbarinov/tunnel-server/dist/index.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tunnel-server

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/tunnel-server

[Install]
WantedBy=multi-user.target
```

#### 4. Create Service User (Optional but Recommended)

```bash
sudo useradd -r -s /bin/false tunnel-server
sudo chown -R tunnel-server:tunnel-server /opt/tunnel-server
```

#### 5. Enable and Start the Service

```bash
# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable tunnel-server

# Start the service
sudo systemctl start tunnel-server

# Check status
sudo systemctl status tunnel-server

# View logs
sudo journalctl -u tunnel-server -f
```

#### 6. Service Management Commands

```bash
# Start service
sudo systemctl start tunnel-server

# Stop service
sudo systemctl stop tunnel-server

# Restart service
sudo systemctl restart tunnel-server

# Reload service (if supported)
sudo systemctl reload tunnel-server

# Check status
sudo systemctl status tunnel-server

# View logs
sudo journalctl -u tunnel-server
sudo journalctl -u tunnel-server -n 100  # Last 100 lines
sudo journalctl -u tunnel-server --since "1 hour ago"

# Disable auto-start on boot
sudo systemctl disable tunnel-server
```

### Option 2: PM2 Process Manager

```bash
# Install Node.js 20+
npm install
npm run build

# Install PM2 globally
npm install -g pm2

# Start with PM2
pm2 start dist/index.js --name tunnel-server --env production

# Save PM2 configuration
pm2 save

# Setup PM2 to start on system boot
pm2 startup
pm2 save
```

### Option 3: nginx + Let's Encrypt (Production Deployment)

This is the recommended method for production deployments with SSL/TLS certificates.

#### Prerequisites

- Ubuntu/Debian server with root access
- Domain name pointing to your server's IP address
- SSH access configured (may use non-standard port)
- Ports 80 and 443 open in firewall (SSH port should already be open)

#### Step 1: Install nginx and Certbot

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install nginx
sudo apt install nginx -y

# Install Certbot for Let's Encrypt
sudo apt install certbot python3-certbot-nginx -y
```

#### Step 2: Configure DNS

Ensure your domain (e.g., `example.com`) points to your server's IP address:

```bash
# Verify DNS resolution
dig example.com
# Should return your server's IP
```

#### Step 3: Create nginx Configuration

Create `/etc/nginx/sites-available/tunnel-server`:

```bash
sudo nano /etc/nginx/sites-available/tunnel-server
```

Add the following configuration:

```nginx
# WebSocket upgrade mapping
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name example.com;

    # Let's Encrypt will use this for validation
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect HTTP to HTTPS (after SSL is configured)
    # Uncomment after running certbot:
    # return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name example.com;

    # SSL certificates (will be added by certbot)
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # SSL configuration (modern, secure)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Proxy all requests to tunnel server
    location / {
        proxy_pass http://127.0.0.1:3000;  # Internal port (matches PORT in .env)
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        
        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts for long-lived WebSocket connections
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
    }
}
```

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/tunnel-server /etc/nginx/sites-enabled/
sudo nginx -t  # Test configuration
sudo systemctl reload nginx
```

#### Step 4: Obtain SSL Certificate

```bash
# Request certificate from Let's Encrypt
sudo certbot --nginx -d example.com

# Follow the prompts:
# - Enter email address
# - Agree to terms
# - Choose whether to redirect HTTP to HTTPS (recommended: Yes)
```

Certbot will automatically:
- Obtain the SSL certificate
- Update nginx configuration
- Set up automatic renewal

#### Step 5: Configure Tunnel Server

Create `/etc/tunnel-server/.env`:

```bash
sudo mkdir -p /etc/tunnel-server
sudo nano /etc/tunnel-server/.env
```

Add configuration:

```bash
PORT=3000
HOST=127.0.0.1
NODE_ENV=production
PUBLIC_HOST=example.com:443
PUBLIC_PROTOCOL=https
TUNNEL_REGISTRATION_API_KEY=your-secret-api-key-here  # Generate with: openssl rand -hex 32
```

**Important:** Generate a strong API key securely:

```bash
# Generate 256-bit random key (recommended)
openssl rand -hex 32

# Alternative: base64 encoded (256 bits)
openssl rand -base64 32

# Copy the output and paste it as the TUNNEL_REGISTRATION_API_KEY value
# Example output: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2
```

**Security Best Practices:**
- Use a different key for each environment (dev/staging/production)
- Never commit keys to version control
- Rotate keys periodically (every 90 days recommended)
- Store keys securely (use `.env` file with proper permissions: `chmod 600`)

Set permissions:

```bash
sudo chmod 600 /etc/tunnel-server/.env
sudo chown root:root /etc/tunnel-server/.env
```

#### Step 6: Install and Configure Tunnel Server

Follow the systemd service setup (Option 1) above, using the `.env` file created in Step 5.

#### Step 7: Verify SSL Auto-Renewal

Let's Encrypt certificates expire every 90 days. Certbot sets up automatic renewal:

```bash
# Test renewal process
sudo certbot renew --dry-run

# Check renewal timer
sudo systemctl status certbot.timer
```

#### Step 8: Firewall Configuration

Configure the firewall to allow only essential services from the internet:
1. **SSH** (for server administration) - may use non-standard port
2. **HTTP (80)** and **HTTPS (443)** for nginx
3. **Block all other ports** including the tunnel server port (e.g., 3000) from external access
4. Only allow localhost connections to the tunnel server port

**Important:** Before configuring the firewall, ensure you know your SSH port. If SSH uses a non-standard port, configure it first to avoid being locked out!

**Using UFW (Ubuntu/Debian):**

```bash
# IMPORTANT: Configure SSH first to avoid lockout!
# Check your SSH port (default is 22, but may be non-standard)
sudo grep -E "^Port" /etc/ssh/sshd_config || echo "Using default port 22"

# Allow SSH (replace 22 with your actual SSH port if different)
# If SSH uses a non-standard port, use that port number instead
SSH_PORT=22  # Change this to your actual SSH port if different
sudo ufw allow ${SSH_PORT}/tcp comment 'SSH access'

# Allow HTTP and HTTPS (for nginx)
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Explicitly deny tunnel server port from external access
# This ensures even if HOST is changed to 0.0.0.0, the port is blocked
sudo ufw deny 3000/tcp comment 'Block tunnel server from internet'

# Allow localhost connections (for nginx to connect to tunnel server)
# Note: localhost connections are typically allowed by default, but this makes it explicit
sudo ufw allow from 127.0.0.1 to any port 3000 comment 'Allow localhost to tunnel server'

# Set default policies (deny incoming, allow outgoing)
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Enable firewall (if not already enabled)
# WARNING: Make sure SSH port is allowed before enabling!
sudo ufw enable

# Verify firewall rules
sudo ufw status verbose
```

**Using iptables (Alternative):**

```bash
# IMPORTANT: Configure SSH first to avoid lockout!
# Check your SSH port (default is 22, but may be non-standard)
SSH_PORT=22  # Change this to your actual SSH port if different

# Set default policies
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# Allow established and related connections
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback (localhost) traffic
sudo iptables -A INPUT -i lo -j ACCEPT

# Allow SSH (replace 22 with your actual SSH port if different)
sudo iptables -A INPUT -p tcp --dport ${SSH_PORT} -j ACCEPT

# Allow HTTP and HTTPS
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Block tunnel server port from external access
sudo iptables -A INPUT -p tcp --dport 3000 ! -s 127.0.0.1 -j DROP

# Allow localhost connections to tunnel server
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 3000 -j ACCEPT

# Save iptables rules (Ubuntu/Debian)
sudo apt install iptables-persistent
sudo netfilter-persistent save

# Or for CentOS/RHEL:
# sudo service iptables save
```

**Finding Your SSH Port:**

```bash
# Check SSH configuration for port
sudo grep -E "^Port" /etc/ssh/sshd_config

# Or check what port SSH is actually listening on
sudo ss -tlnp | grep sshd
# or
sudo netstat -tlnp | grep sshd
```

**Common Non-Standard SSH Ports:**
- 2222
- 2200
- 2022
- 22022

If your SSH uses a non-standard port, make sure to use that port number in the firewall configuration above.

**Verification:**

```bash
# Verify SSH access (from another machine)
# Replace YOUR_SERVER_IP and SSH_PORT with actual values
ssh -p SSH_PORT user@YOUR_SERVER_IP
# Should connect successfully

# Test that tunnel server port is blocked from external access
# From another machine or using external IP:
curl http://YOUR_SERVER_IP:3000/health
# Should timeout or be refused

# Test that localhost can access (from the server itself):
curl http://127.0.0.1:3000/health
# Should work

# Test that nginx can proxy to tunnel server:
curl https://example.com/health
# Should work via nginx

# Verify firewall rules are active
sudo ufw status verbose
# Should show only SSH, HTTP (80), and HTTPS (443) allowed from internet
# Tunnel server port (3000) should be denied or not listed
```

**Important Security Notes:**
- **SSH Port Configuration**: Always configure SSH access first before enabling the firewall. If SSH uses a non-standard port, use that port number in the firewall rules. Failure to do so may result in being locked out of the server.
- The tunnel server should **never** be directly accessible from the internet
- Only nginx (running on the same host) should be able to connect to the tunnel server
- Setting `HOST=127.0.0.1` in the `.env` file provides defense-in-depth, but firewall rules are the primary security measure
- If you accidentally set `HOST=0.0.0.0`, the firewall rules will still block external access
- The firewall should only allow SSH, HTTP (80), and HTTPS (443) from the internet. All other ports should be blocked.

#### Verification

1. Check tunnel server is running:
   ```bash
   sudo systemctl status tunnel-server
   ```

2. Check nginx is running:
   ```bash
   sudo systemctl status nginx
   ```

3. Test HTTPS endpoint:
   ```bash
   curl https://example.com/health
   ```

4. Check SSL certificate:
   ```bash
   openssl s_client -connect example.com:443 -servername example.com
   ```

### Option 4: Cloudflare Tunnel

```bash
brew install cloudflared
cloudflared tunnel login
cloudflared tunnel create laptop-tunnel
cloudflared tunnel route dns laptop-tunnel yourdomain.com
cloudflared tunnel run laptop-tunnel
```

## Troubleshooting

### .npmrc Issues

**Problem: `401 Unauthorized` when installing**
- Verify your GitHub token has `read:packages` permission
- Check that the token hasn't expired
- Ensure `.npmrc` file has correct format (no extra spaces, correct registry URL)

**Problem: `404 Not Found` when installing**
- Verify the package name: `@rbarinov/tunnel-server`
- Check that the package has been published to GitHub Packages
- Ensure you're using the correct scope in `.npmrc`: `@rbarinov:registry=...`

**Problem: Token exposed in logs**
- Never commit `.npmrc` with tokens to git
- Use environment variables or secret management for CI/CD
- Rotate tokens if accidentally exposed

### systemd Service Issues

**Problem: Service fails to start**
```bash
# Check service status
sudo systemctl status tunnel-server

# View detailed logs
sudo journalctl -u tunnel-server -n 50 --no-pager

# Check if Node.js is in PATH
which node

# Verify file permissions
ls -la /opt/tunnel-server
```

**Problem: Permission denied errors**
```bash
# Ensure service user owns the directory
sudo chown -R tunnel-server:tunnel-server /opt/tunnel-server

# Check .env file permissions
sudo chmod 600 /etc/tunnel-server/.env
sudo chown root:root /etc/tunnel-server/.env
```

**Problem: Service can't find the package**
- Verify the path in `ExecStart` matches your installation
- For global installs, use: `npm root -g` to find the path
- For local installs, ensure path points to `node_modules/@rbarinov/tunnel-server/dist/index.js`

**Problem: Environment variables not loading**
- Verify `EnvironmentFile=/etc/tunnel-server/.env` in service file
- Check `.env` file syntax (no spaces around `=`)
- Restart service after changing `.env`: `sudo systemctl restart tunnel-server`

## Architecture

### System Overview

```
[Mobile Device] → [Tunnel Server] → [Laptop]
                         ↓
                  WebSocket Hub
                         ↓
                  HTTP Proxy
```

### Modular Architecture

The tunnel-server has been refactored into a modular, maintainable architecture following TypeScript best practices:

```
src/
├── index.ts                    # Main entry point (132 lines)
├── server.ts                   # Express & HTTP server setup
├── config/
│   └── Config.ts               # Configuration management
├── types/
│   └── index.ts                # Type definitions
├── schemas/
│   └── tunnelSchemas.ts        # Zod validation schemas
├── utils/
│   └── logger.ts               # Structured JSON logging
├── tunnel/
│   └── TunnelManager.ts        # Tunnel connection management
├── websocket/
│   ├── WebSocketServer.ts      # WebSocket server setup
│   ├── handlers/
│   │   ├── tunnelHandler.ts    # Tunnel message handler
│   │   ├── streamHandler.ts    # Stream connection handler
│   │   └── streamManager.ts   # Stream connection management
│   └── heartbeat/
│       └── HeartbeatManager.ts # Heartbeat management
├── proxy/
│   └── HttpProxy.ts            # HTTP request proxying
├── routes/
│   ├── tunnel.ts               # Tunnel creation routes
│   ├── health.ts               # Health check routes
│   └── recording.ts           # Recording SSE routes
└── errors/
    └── TunnelError.ts          # Custom error types
```

### Key Features

- **Modular Design**: 17 focused modules with single responsibilities
- **Type Safety**: Zero `any` types, full TypeScript strict mode, Zod runtime validation
- **Structured Logging**: JSON-formatted logs with context and sanitized secrets
- **Error Handling**: Custom error types with proper HTTP status codes
- **Testing**: 49 unit tests with ~60% code coverage
- **Separation of Concerns**: Clear module boundaries and dependencies

### Testing

The project includes comprehensive test coverage:

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Generate coverage report
npm run test:coverage
```

**Test Coverage:**
- Config: 95.23%
- Errors: 100%
- Schemas: 100%
- TunnelManager: 100%
- Logger: 100%
- Routes: 43.1% (tunnel.ts: 92.59%)

**Test Structure:**
- Unit tests for each module in `__tests__/` directories
- Tests use Jest with ES modules support
- All tests validate both success and error cases

### Development

#### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Generate coverage report
npm run test:coverage
```

#### Type Checking

```bash
# Type check without building
npm run type-check
```

#### Building

```bash
# Build TypeScript to JavaScript
npm run build

# Build in watch mode
npm run build:watch
```

#### Development Mode

```bash
# Run with hot reload (tsx)
npm run dev
```

### Code Quality

- **TypeScript**: Strict mode enabled, no `any` types
- **Validation**: Zod schemas for all inputs
- **Logging**: Structured JSON logging (no console.log)
- **Error Handling**: Custom error types with proper status codes
- **Testing**: Comprehensive unit test coverage
- **Documentation**: JSDoc comments for all public APIs

### Module Responsibilities

- **Config**: Environment variable loading and validation
- **Logger**: Structured JSON logging with secret sanitization
- **TunnelManager**: Tunnel connection registration and lifecycle
- **WebSocketServer**: WebSocket connection routing and setup
- **TunnelHandler**: Processing messages from laptop connections
- **StreamHandler**: Managing terminal and recording stream connections
- **StreamManager**: Broadcasting output to connected clients
- **HeartbeatManager**: Connection health monitoring and cleanup
- **HttpProxy**: HTTP request forwarding to laptop via WebSocket
- **Routes**: Express route handlers with validation
- **Errors**: Custom error types for proper error handling
