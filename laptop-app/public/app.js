// Use current origin for API calls (works with any port)
const API_BASE = window.location.origin;
let currentSessionId = null;
let ws = null;
let term = null;
let fitAddon = null;

const TERMINAL_TYPE_LABELS = {
    regular: '💻 Regular',
    cursor_agent: '🤖 Cursor Agent',
    cursor_cli: '🤖 Cursor CLI (headless)',
    claude_cli: '🪄 Claude CLI (headless)'
};

function getTypeLabel(type) {
    return TERMINAL_TYPE_LABELS[type] || TERMINAL_TYPE_LABELS.regular;
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    loadSessions();
    
    document.getElementById('refreshBtn').addEventListener('click', loadSessions);
    document.getElementById('createBtn').addEventListener('click', createSession);
    document.getElementById('closeDetailBtn').addEventListener('click', closeSessionDetail);
    document.getElementById('deleteSessionBtn').addEventListener('click', deleteCurrentSession);
    
    // Handle window resize for terminal
    let resizeTimeout;
    window.addEventListener('resize', () => {
        clearTimeout(resizeTimeout);
        resizeTimeout = setTimeout(() => {
            if (fitAddon) {
                fitAddon.fit();
            }
        }, 100);
    });
});

async function loadSessions() {
    try {
        const response = await fetch(`${API_BASE}/terminal/list`);
        const data = await response.json();
        
        const sessionsList = document.getElementById('sessionsList');
        
        if (data.sessions && data.sessions.length > 0) {
            sessionsList.innerHTML = data.sessions.map(session => {
                const typeLabel = getTypeLabel(session.terminal_type);
                const nameLabel = session.name ? escapeHtml(session.name) : session.session_id;
                return `
                <div class="session-card" onclick="openSession('${session.session_id}')">
                    <h3>${nameLabel}</h3>
                    <div class="session-id">${session.session_id}</div>
                    <div class="session-type">${typeLabel}</div>
                    <div class="session-dir">${escapeHtml(session.working_dir)}</div>
                    <div class="session-time">Created: ${new Date(session.created_at || Date.now()).toLocaleString()}</div>
                </div>
            `;
            }).join('');
        } else {
            sessionsList.innerHTML = '<div class="loading">No active sessions. Create a new one!</div>';
        }
    } catch (error) {
        console.error('Failed to load sessions:', error);
        document.getElementById('sessionsList').innerHTML = 
            '<div class="loading" style="color: #dc3545;">Error loading sessions. Make sure the server is running.</div>';
    }
}

async function createSession() {
    try {
        const typeInput = prompt('Terminal type (regular, cursor_agent, cursor_cli, claude_cli):', 'cursor_cli');
        const normalizedType = (typeInput || '').trim().toLowerCase();
        const terminalType = TERMINAL_TYPE_LABELS[normalizedType] ? normalizedType : 'regular';
        const name = prompt('Terminal name (optional):') || undefined;
        const workingDir = prompt('Working directory (leave empty for home):') || undefined;
        
        const response = await fetch(`${API_BASE}/terminal/create`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ 
                terminal_type: terminalType,
                working_dir: workingDir,
                name: name
            })
        });
        
        const data = await response.json();
        
        if (response.ok) {
            await loadSessions();
            openSession(data.session_id);
        } else {
            alert('Failed to create session: ' + (data.error || 'Unknown error'));
        }
    } catch (error) {
        console.error('Failed to create session:', error);
        alert('Failed to create session. Make sure the server is running.');
    }
}

function openSession(sessionId) {
    currentSessionId = sessionId;
    
    // Load session info
    loadSessions().then(() => {
        fetch(`${API_BASE}/terminal/list`)
            .then(res => res.json())
            .then(data => {
                const session = data.sessions.find(s => s.session_id === sessionId);
                if (session) {
                    const sessionTitle = session.name || sessionId;
                    const typeLabel = getTypeLabel(session.terminal_type);
                    document.getElementById('sessionTitle').textContent = `Session: ${sessionTitle}`;
                    document.getElementById('sessionId').textContent = sessionId;
                    document.getElementById('sessionName').textContent = session.name || '-';
                    document.getElementById('terminalType').textContent = typeLabel;
                    document.getElementById('workingDir').textContent = session.working_dir;
                    document.getElementById('createdAt').textContent = new Date(session.created_at || Date.now()).toLocaleString();
                }
            });
    });
    
    // Show detail view
    document.getElementById('sessionsList').classList.add('hidden');
    document.getElementById('sessionDetail').classList.remove('hidden');
    
    // Initialize xterm.js terminal
    initTerminal();
    
    // Connect WebSocket for real-time output
    connectWebSocket(sessionId);
    
    // Load initial history into terminal
    loadHistoryIntoTerminal(sessionId);
}

function initTerminal() {
    // Clean up existing terminal
    if (term) {
        term.dispose();
    }
    
    const terminalElement = document.getElementById('terminal');
    terminalElement.innerHTML = ''; // Clear any existing content
    
    // Create new xterm.js terminal
    term = new Terminal({
        cursorBlink: true,
        fontSize: 14,
        fontFamily: 'Menlo, Monaco, "Courier New", monospace',
        theme: {
            background: '#1e1e1e',
            foreground: '#d4d4d4',
            cursor: '#aeafad',
            selection: '#264f78',
            black: '#000000',
            red: '#cd3131',
            green: '#0dbc79',
            yellow: '#e5e510',
            blue: '#2472c8',
            magenta: '#bc3fbc',
            cyan: '#11a8cd',
            white: '#e5e5e5',
            brightBlack: '#666666',
            brightRed: '#f14c4c',
            brightGreen: '#23d18b',
            brightYellow: '#f5f543',
            brightBlue: '#3b8eea',
            brightMagenta: '#d670d6',
            brightCyan: '#29b8db',
            brightWhite: '#e5e5e5'
        }
    });
    
    // Add fit addon for auto-resize
    // FitAddon might be exposed differently depending on CDN version
    try {
        fitAddon = new (window.FitAddon || FitAddon)();
        term.loadAddon(fitAddon);
    } catch (e) {
        console.warn('FitAddon not available, terminal will not auto-resize:', e);
    }
    
    // Open terminal
    term.open(terminalElement);
    
    // Fit terminal to container
    if (fitAddon) {
        fitAddon.fit();
    }
    
    // Handle user input
    term.onData((data) => {
        // Send input to terminal via WebSocket
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({
                type: 'input',
                data: data
            }));
        }
    });
    
    // Handle terminal resize
    term.onResize((size) => {
        // Send resize to server
        if (currentSessionId) {
            fetch(`${API_BASE}/terminal/${currentSessionId}/resize`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    cols: size.cols,
                    rows: size.rows
                })
            }).catch(err => console.error('Failed to resize terminal:', err));
        }
    });
    
    // Focus terminal
    term.focus();
}

function closeSessionDetail() {
    currentSessionId = null;
    document.getElementById('sessionsList').classList.remove('hidden');
    document.getElementById('sessionDetail').classList.add('hidden');
    
    // Close WebSocket
    if (ws) {
        ws.close();
        ws = null;
    }
    
    // Dispose terminal
    if (term) {
        term.dispose();
        term = null;
        fitAddon = null;
    }
}

async function deleteCurrentSession() {
    if (!currentSessionId) return;
    
    if (!confirm(`Are you sure you want to delete session ${currentSessionId}?`)) {
        return;
    }
    
    try {
        const response = await fetch(`${API_BASE}/terminal/${currentSessionId}`, {
            method: 'DELETE'
        });
        
        if (response.ok) {
            closeSessionDetail();
            loadSessions();
        } else {
            const data = await response.json();
            alert('Failed to delete session: ' + (data.error || 'Unknown error'));
        }
    } catch (error) {
        console.error('Failed to delete session:', error);
        alert('Failed to delete session.');
    }
}

// Commands are now sent directly through the interactive terminal
// This function is no longer needed but kept for compatibility
async function executeCommand() {
    // Commands are handled interactively through xterm.js
    if (term) {
        term.focus();
    }
}


async function loadHistoryIntoTerminal(sessionId) {
    if (!sessionId || !term) return;
    
    try {
        const response = await fetch(`${API_BASE}/terminal/${sessionId}/history`);
        const data = await response.json();
        
        if (response.ok && data.history && term) {
            // Write history to terminal (xterm.js handles ANSI sequences)
            term.write(data.history);
        }
    } catch (error) {
        console.error('Failed to load history:', error);
    }
}

function connectWebSocket(sessionId) {
    // Close existing connection
    if (ws) {
        ws.close();
    }
    
    // Connect to WebSocket using current origin
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${wsProtocol}//${window.location.host}/terminal/${sessionId}/stream`;
    ws = new WebSocket(wsUrl);
    
    ws.onopen = () => {
        console.log('WebSocket connected');
    };
    
    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data.type === 'output' && data.data && term) {
            // Write output directly to xterm.js terminal
            // xterm.js handles ANSI escape sequences automatically
            term.write(data.data);
        }
    };
    
    ws.onerror = (error) => {
        console.error('WebSocket error:', error);
    };
    
    ws.onclose = () => {
        console.log('WebSocket closed');
    };
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
