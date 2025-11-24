import { spawn, IPty } from 'node-pty';
import os from 'os';
import type { TunnelClient } from '../tunnel/TunnelClient.js';
import { StateManager, type TerminalSessionState } from '../storage/StateManager.js';
import { HeadlessCliRunner, type HeadlessTerminalType } from './HeadlessCliRunner.js';

type TerminalType = 'regular' | 'cursor_agent' | HeadlessTerminalType;

interface TerminalSession {
  sessionId: string;
  pty?: IPty;
  workingDir: string;
  createdAt: number;
  outputBuffer: string[];
  terminalType: TerminalType;
  name?: string;
  cursorAgentWorkingDir?: string;
  headless?: {
    isRunning: boolean;
  };
}

export class TerminalManager {
  private sessions = new Map<string, TerminalSession>();
  private outputListeners = new Map<string, Set<(data: string) => void>>();
  private tunnelClient: TunnelClient | null = null;
  private stateManager: StateManager;
  private globalOutputListeners = new Set<(session: TerminalSession, data: string) => void>();
  private globalInputListeners = new Set<(session: TerminalSession, data: string) => void>();
  private sessionDestroyedListeners = new Set<(sessionId: string) => void>();
  private headlessRunner = new HeadlessCliRunner();
  
  constructor(stateManager: StateManager) {
    this.stateManager = stateManager;
  }
  
  async restoreSessions(): Promise<void> {
    console.log('🔄 Attempting to restore terminal sessions...');
    const state = await this.stateManager.loadState();
    
    if (!state || !state.sessions || state.sessions.length === 0) {
      console.log('📂 No sessions to restore');
      return;
    }
    
    console.log(`🔄 Found ${state.sessions.length} sessions to restore`);
    console.log('⚠️  Note: Sessions cannot be restored without tmux. Creating new sessions instead.');
    
    // Without tmux, we cannot restore existing sessions as PTY connections are lost
    // Clear the state and let users create new sessions
    await this.stateManager.saveSessionsState([]);
  }
  
  private async saveSessionsState(): Promise<void> {
    const sessions: TerminalSessionState[] = Array.from(this.sessions.values()).map(s => ({
      sessionId: s.sessionId,
      workingDir: s.workingDir,
      createdAt: s.createdAt,
      terminalType: s.terminalType,
      name: s.name,
      cursorAgentWorkingDir: s.cursorAgentWorkingDir
    }));
    
    await this.stateManager.saveSessionsState(sessions);
  }
  
  setTunnelClient(tunnelClient: TunnelClient): void {
    this.tunnelClient = tunnelClient;
  }
  
  writeInput(sessionId: string, data: string, isCommand: boolean = false): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      if (!session.pty) {
        console.warn(`⚠️  Cannot write input to non-interactive session ${sessionId}`);
        return;
      }
      // Normalize input: convert \n to \r for Enter key
      // This fixes issues when cursor-agent or other tools modify Enter key behavior
      // Terminal expects \r (carriage return) to execute commands, not \n (newline)
      let normalizedData = data;
      
      // Log original data for debugging
      const originalBytes = Array.from(data).map(c => c.charCodeAt(0));
      console.log(`⌨️  Raw input: ${JSON.stringify(data)} (bytes: ${originalBytes.join(', ')})`);
      
      // Handle cursor-agent case: it sends \n\n instead of \r
      // Also handle SwiftTerm which may send \n instead of \r
      // Always convert \n to \r if there's no \r in the data
      // This ensures Enter key always sends \r (carriage return) which terminals expect
      if (!normalizedData.includes('\r')) {
        // If there's no \r in the data, replace all \n sequences with \r
        // This handles:
        // - SwiftTerm sending \n instead of \r
        // - cursor-agent sending \n\n instead of \r
        // - Any other case where \n is used instead of \r
        normalizedData = normalizedData.replace(/\n+/g, '\r');
      } else if (normalizedData.endsWith('\n') && !normalizedData.endsWith('\r\n')) {
        // If data has \r but ends with \n (not \r\n), replace trailing \n with \r
        normalizedData = normalizedData.slice(0, -1) + '\r';
      }
      
      // Only add \r at the end for complete commands (HTTP API), not for character-by-character input
      // Character-by-character input should only have \r when user presses Enter
      if (isCommand && !normalizedData.endsWith('\r') && !normalizedData.endsWith('\r\n')) {
        // This is a complete command from HTTP API, ensure it ends with \r for execution
        normalizedData += '\r';
      }
      
      // Log normalized data
      if (normalizedData !== data) {
        const normalizedBytes = Array.from(normalizedData).map(c => c.charCodeAt(0));
        console.log(`⌨️  Normalized: ${JSON.stringify(normalizedData)} (bytes: ${normalizedBytes.join(', ')})`);
      }
      
      // Write to PTY - this is what actually sends data to the terminal
      // For cursor-agent, the command should be sent as-is with \r at the end
      session.pty.write(normalizedData);

      // Notify global input listeners (recording stream manager, etc.)
      this.globalInputListeners.forEach(listener => {
        try {
          listener(session, normalizedData);
        } catch (error) {
          console.error('❌ Global input listener error:', error);
        }
      });
      
      // Log what was actually written to PTY
      console.log(`📝 Written to PTY: ${normalizedData.length} bytes, ends with: ${normalizedData.slice(-5).split('').map(c => `'${c}'(${c.charCodeAt(0)})`).join(' ')}`);
    }
  }
  
  resizeTerminal(sessionId: string, cols: number, rows: number): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      if (!session.pty) {
        console.warn(`⚠️  Cannot resize non-interactive session ${sessionId}`);
        return;
      }
      try {
        // Resize the PTY
        session.pty.resize(cols, rows);
        console.log(`📐 Resized terminal ${sessionId}: ${cols}x${rows}`);
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        console.error(`❌ Failed to resize PTY for ${sessionId}: ${errorMessage}`);
        
        // Try to recover by checking if PTY is still alive
        if (errorMessage.includes('EBADF')) {
          console.error(`⚠️  PTY is closed for session ${sessionId}, session may be dead`);
        }
      }
    } else {
      console.warn(`⚠️  Cannot resize - session ${sessionId} not found`);
    }
  }
  
  async createSession(
    terminalType: TerminalType = 'regular',
    workingDir?: string,
    name?: string
  ): Promise<{ sessionId: string; workingDir: string; terminalType: TerminalType; name?: string }> {
    const sessionId = `session-${Date.now()}`;
    const cwd = workingDir || process.env.HOME || os.homedir();
    
    const session: TerminalSession = {
      sessionId,
      workingDir: cwd,
      createdAt: Date.now(),
      outputBuffer: [],
      terminalType,
      name,
      cursorAgentWorkingDir: terminalType === 'cursor_agent' ? cwd : undefined,
      headless: this.isHeadlessTerminal(terminalType)
        ? {
            isRunning: false
          }
        : undefined
    };

    if (this.isHeadlessTerminal(terminalType)) {
      this.sessions.set(sessionId, session);
      await this.saveSessionsState();
      console.log(`✅ Created headless session: ${sessionId} (${terminalType}) in ${cwd}`);
      return { sessionId, workingDir: cwd, terminalType, name };
    }

    // Create direct PTY session (no tmux)
    const shell = process.env.SHELL || (os.platform() === 'win32' ? 'powershell.exe' : 'bash');
    
    // Configure environment to ensure proper shell prompt
    const env = {
      ...process.env,
      TERM: 'xterm-256color',
      TERM_PROGRAM: '',
      VTE_VERSION: '',
      ZDOTDIR: process.env.ZDOTDIR || process.env.HOME,
      ZSH_DISABLE_COMPFIX: 'true',
    } as Record<string, string>;
    
    delete env.BASH_ENV;
    delete env.ENV;
    
    const shellArgs: string[] = [];
    if (shell.includes('zsh')) {
      shellArgs.push('-i');
    } else if (shell.includes('bash')) {
      shellArgs.push('-i');
    }
    
    const pty = spawn(shell, shellArgs, {
      name: 'xterm-256color',
      cols: 80,
      rows: 30,
      cwd,
      env
    });
    session.pty = pty;
    
    // Capture output
    pty.onData((data) => {
      session.outputBuffer.push(data);
      
      // Keep only last 10000 lines for history
      if (session.outputBuffer.length > 10000) {
        session.outputBuffer.shift();
      }
      
      // Stream to tunnel (for iPhone)
      if (this.tunnelClient) {
        this.tunnelClient.sendTerminalOutput(sessionId, data);
      }
      
      // Notify listeners (for WebSocket streaming)
      const listeners = this.outputListeners.get(sessionId);
      if (listeners) {
        listeners.forEach(listener => listener(data));
      }

      // Notify global output listeners
      this.globalOutputListeners.forEach(listener => {
        try {
          listener(session, data);
        } catch (error) {
          console.error('❌ Global output listener error:', error);
        }
      });
    });
    
    this.sessions.set(sessionId, session);
    
    // Save sessions to state file
    await this.saveSessionsState();
    
    console.log(`✅ Created terminal session: ${sessionId} (${terminalType}) in ${cwd}`);
    
    // If cursor_agent type, automatically start cursor-agent command
    if (terminalType === 'cursor_agent') {
      // Wait a bit for shell to initialize, then start cursor-agent
      setTimeout(() => {
        console.log(`🚀 Starting cursor-agent in session ${sessionId}...`);
        this.writeInput(sessionId, 'cursor-agent\r', true);
      }, 500);
    }
    
    return { sessionId, workingDir: cwd, terminalType, name };
  }
  
  executeCommand(sessionId: string, command: string): Promise<string> {
    const session = this.sessions.get(sessionId);
    
    if (!session) {
      throw new Error('Session not found');
    }

    if (this.isHeadlessTerminal(session.terminalType)) {
      return this.executeHeadlessCommand(session, command);
    }
    
    console.log(`📝 executeCommand called for ${sessionId}: ${JSON.stringify(command)}`);
    console.log(`📝 Command length: ${command.length}, bytes: ${Array.from(command).map(c => c.charCodeAt(0)).join(', ')}`);
    
    // Use writeInput with isCommand=true to ensure proper normalization and \r at the end
    // This is especially important when cursor-agent is active
    // Command may come with \n\n from iPhone app, which needs to be normalized
    this.writeInput(sessionId, command, true);
    
    console.log(`✅ Command written to PTY for ${sessionId}`);
    
    // Wait a bit for output (simple approach)
    // In production, you'd want more sophisticated output detection
    return new Promise((resolve) => {
      setTimeout(() => {
        // Return only the new output since command was written
        // For now, return empty since we're streaming via WebSocket
        resolve('');
      }, 100);
    });
  }

  private async executeHeadlessCommand(session: TerminalSession, command: string): Promise<string> {
    const prompt = command.trim();
    if (!prompt) {
      throw new Error('Command is required for headless sessions');
    }

    if (!session.headless) {
      session.headless = { isRunning: false };
    }

    if (session.headless.isRunning) {
      throw new Error('Headless session is busy. Please wait for the current command to finish.');
    }

    session.headless.isRunning = true;
    this.notifyHeadlessCommand(session, prompt);

    this.headlessRunner
      .run({
        sessionId: session.sessionId,
        workingDir: session.workingDir,
        terminalType: session.terminalType as HeadlessTerminalType,
        prompt,
        onDelta: (text) => this.emitHeadlessOutput(session, text),
        onError: (message) => this.emitHeadlessOutput(session, `⚠️ ${message}`)
      })
      .then(() => {
        session.headless!.isRunning = false;
        this.emitHeadlessOutput(session, '✅ Completed');
      })
      .catch((error) => {
        session.headless!.isRunning = false;
        const message = error instanceof Error ? error.message : String(error);
        this.emitHeadlessOutput(session, `❌ ${message}`);
      });

    return 'Headless command started';
  }
  
  private notifyHeadlessCommand(session: TerminalSession, command: string): void {
    const normalized = `${command}\r`;
    this.globalInputListeners.forEach(listener => {
      try {
        listener(session, normalized);
      } catch (error) {
        console.error('❌ Global input listener error:', error);
      }
    });
  }

  private emitHeadlessOutput(session: TerminalSession, data: string): void {
    const text = data?.trim();
    if (!text) {
      return;
    }

    session.outputBuffer.push(text);
    if (session.outputBuffer.length > 10000) {
      session.outputBuffer.shift();
    }

    if (this.tunnelClient) {
      this.tunnelClient.sendTerminalOutput(session.sessionId, text);
    }

    const listeners = this.outputListeners.get(session.sessionId);
    if (listeners) {
      listeners.forEach(listener => listener(text));
    }

    this.globalOutputListeners.forEach(listener => {
      try {
        listener(session, text);
      } catch (error) {
        console.error('❌ Global output listener error:', error);
      }
    });
  }
  
  listSessions(): Array<{ sessionId: string; workingDir: string; createdAt: number; terminalType: TerminalType; name?: string }> {
    return Array.from(this.sessions.values()).map(s => ({
      sessionId: s.sessionId,
      workingDir: s.workingDir,
      createdAt: s.createdAt,
      terminalType: s.terminalType,
      name: s.name
    }));
  }
  
  renameSession(sessionId: string, name: string): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.name = name;
      this.saveSessionsState().catch(err => {
        console.error('Failed to save sessions state:', err);
      });
      console.log(`✏️  Renamed session ${sessionId} to: ${name}`);
    } else {
      throw new Error('Session not found');
    }
  }
  
  getSession(sessionId: string): TerminalSession | undefined {
    return this.sessions.get(sessionId);
  }
  
  getHistory(sessionId: string): string {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return '';
    }
    
    // Return output buffer history
    return session.outputBuffer.join('');
  }
  
  addOutputListener(sessionId: string, listener: (data: string) => void): void {
    if (!this.outputListeners.has(sessionId)) {
      this.outputListeners.set(sessionId, new Set());
    }
    this.outputListeners.get(sessionId)!.add(listener);
  }
  
  removeOutputListener(sessionId: string, listener: (data: string) => void): void {
    this.outputListeners.get(sessionId)?.delete(listener);
  }
  
  destroySession(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.pty?.kill();
      this.sessions.delete(sessionId);
      this.outputListeners.delete(sessionId);

       this.sessionDestroyedListeners.forEach(listener => {
         try {
           listener(sessionId);
         } catch (error) {
           console.error('❌ Session destroyed listener error:', error);
         }
       });
      
      // Update state file
      this.saveSessionsState().catch(err => {
        console.error('Failed to save sessions state:', err);
      });
      
      console.log(`🗑️  Destroyed session: ${sessionId}`);
    }
  }
  
  cleanup(): void {
    this.sessions.forEach((session) => {
      session.pty?.kill();
    });
    this.sessions.clear();
    this.outputListeners.clear();
  }

  addGlobalOutputListener(listener: (session: TerminalSession, data: string) => void): void {
    this.globalOutputListeners.add(listener);
  }

  addGlobalInputListener(listener: (session: TerminalSession, data: string) => void): void {
    this.globalInputListeners.add(listener);
  }

  addSessionDestroyedListener(listener: (sessionId: string) => void): void {
    this.sessionDestroyedListeners.add(listener);
  }

  private isHeadlessTerminal(type: TerminalType): type is HeadlessTerminalType {
    return type === 'cursor_cli' || type === 'claude_cli';
  }
}

export type { TerminalType };
