import { spawn, IPty } from 'node-pty';
import os from 'os';
import fs from 'fs/promises';
import { execSync } from 'child_process';
import type { TunnelClient } from '../tunnel/TunnelClient';
import { StateManager, type TerminalSessionState } from '../storage/StateManager';
import type { OutputRouter } from '../output/OutputRouter';

type HeadlessTerminalType = 'cursor' | 'claude';
type TerminalType = 'regular' | HeadlessTerminalType;

interface TerminalSession {
  sessionId: string;
  pty?: IPty;
  pid?: number; // Process ID of the PTY process
  processGroupId?: number; // Process group ID for killing all child processes
  workingDir: string;
  createdAt: number;
  outputBuffer: string[];
  inputBuffer: string[]; // Store input commands for history
  terminalType: TerminalType;
  name?: string;
  headless?: {
    isRunning: boolean;
    cliSessionId?: string; // Session ID from CLI (cursor/claude) for context preservation
    completionTimeout?: NodeJS.Timeout; // Timeout for command completion detection
    lastResultSeen?: boolean; // Track if we've seen a result message
  };
}

export class TerminalManager {
  private sessions = new Map<string, TerminalSession>();
  private outputListeners = new Map<string, Set<(data: string) => void>>();
  private tunnelClient: TunnelClient | null = null;
  private outputRouter: OutputRouter | null = null;
  private stateManager: StateManager;
  private globalOutputListeners = new Set<(session: TerminalSession, data: string) => void>();
  private globalInputListeners = new Set<(session: TerminalSession, data: string) => void>();
  private sessionDestroyedListeners = new Set<(sessionId: string) => void>();
  
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
    console.log('⚠️  Note: PTY sessions cannot be restored after application restart. Creating new sessions instead.');

    // PTY connections are lost when application restarts
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
    }));
    
    await this.stateManager.saveSessionsState(sessions);
  }
  
  setTunnelClient(tunnelClient: TunnelClient): void {
    this.tunnelClient = tunnelClient;
  }

  setOutputRouter(outputRouter: OutputRouter): void {
    this.outputRouter = outputRouter;
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
      
      // Log original data for debugging (including backspace)
      const originalBytes = Array.from(data).map(c => c.charCodeAt(0));
      const hasBackspace = originalBytes.some(b => b === 0x08 || b === 0x7f);
      if (hasBackspace) {
        console.log(`⌨️  Backspace detected in input: ${JSON.stringify(data)} (bytes: ${originalBytes.join(', ')})`);
      } else {
        console.log(`⌨️  Raw input: ${JSON.stringify(data)} (bytes: ${originalBytes.join(', ')})`);
      }
      
      // Normalize input: convert \n to \r for Enter key
      // Terminals expect \r (carriage return) to execute commands, not \n (newline)
      if (!normalizedData.includes('\r')) {
        // If there's no \r in the data, replace all \n sequences with \r
        // This handles cases where \n is used instead of \r
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
    // Use provided workingDir, or fallback to WORK_ROOT_PATH env var, or HOME, or system homedir
    const cwd = workingDir || process.env.WORK_ROOT_PATH || process.env.HOME || os.homedir();
    
    // Validate working directory exists
    try {
      const stats = await fs.stat(cwd);
      if (!stats.isDirectory()) {
        throw new Error(`Working directory is not a directory: ${cwd}`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Working directory does not exist: ${cwd}`);
      }
      throw error;
    }
    
    const session: TerminalSession = {
      sessionId,
      workingDir: cwd,
      createdAt: Date.now(),
      outputBuffer: [],
      inputBuffer: [],
      terminalType,
      name,
      // cursorAgentWorkingDir removed - not needed after unification
      headless: this.isHeadlessTerminal(terminalType)
        ? {
            isRunning: false
          }
        : undefined
    };

    // Create PTY for all terminal types (unified logic)
    const pty = this.createPTY(cwd);
    session.pty = pty;
    session.pid = pty.pid;
    
    // Get process group ID (Unix only)
    if (os.platform() !== 'win32' && pty.pid) {
      try {
        session.processGroupId = this.getProcessGroupId(pty.pid);
        console.log(`📊 [${sessionId}] Process group ID: ${session.processGroupId}`);
      } catch (error) {
        console.warn(`⚠️  [${sessionId}] Failed to get process group ID: ${error}`);
      }
    }
    
    // Unified output handling for all terminal types
    this.setupPTYOutputHandler(session);
    
    this.sessions.set(sessionId, session);
    await this.saveSessionsState();
    
    console.log(`✅ Created terminal session: ${sessionId} (${terminalType}) in ${cwd}`);
    
    return { sessionId, workingDir: cwd, terminalType, name };
  }
  
  executeCommand(sessionId: string, command: string): Promise<string> {
    // Log call stack to see where this is called from
    const stack = new Error().stack;
    const caller = stack?.split('\n')[2]?.trim() || 'unknown';
    console.log(`🔍 [${sessionId}] executeCommand called from: ${caller}`);
    console.log(`🔍 [${sessionId}] Command: ${JSON.stringify(command)}`);
    
    const session = this.sessions.get(sessionId);
    
    if (!session) {
      throw new Error('Session not found');
    }
    
    // Log session object reference for debugging (safely, without circular references)
    if (session.headless) {
      const headlessState = {
        isRunning: session.headless.isRunning,
        cliSessionId: session.headless.cliSessionId,
        lastResultSeen: session.headless.lastResultSeen,
        hasCompletionTimeout: !!session.headless.completionTimeout
      };
      console.log(`🔍 [${sessionId}] Session headless state: ${JSON.stringify(headlessState)}`);
    } else {
      console.log(`🔍 [${sessionId}] Session headless state: null`);
    }

    if (this.isHeadlessTerminal(session.terminalType)) {
      // For headless terminals, execute command via CLI (cursor-agent or claude-cli)
      // This is called from Record view (watch/phone) via API
      return this.executeHeadlessCommand(session, command);
    }
    
    // For regular terminals, write command directly to PTY
    console.log(`📝 executeCommand called for ${sessionId}: ${JSON.stringify(command)}`);
    console.log(`📝 Command length: ${command.length}, bytes: ${Array.from(command).map(c => c.charCodeAt(0)).join(', ')}`);
    
    // Use writeInput with isCommand=true to ensure proper normalization and \r at the end
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
      console.log(`🆕 [${session.sessionId}] Initialized headless state`);
    }

    // Log current session_id state before executing command
    const beforeSessionId = session.headless.cliSessionId;
    console.log(`📋 [${session.sessionId}] Before command execution - CLI session_id: ${beforeSessionId || 'none'}`);

    if (session.headless.isRunning) {
      const errorMsg = `Headless session is busy. Please wait for the current command to finish.`;
      console.error(`❌ [${session.sessionId}] ${errorMsg}`);
      throw new Error(errorMsg);
    }

    // Mark as running IMMEDIATELY to prevent duplicate execution
    session.headless.isRunning = true;
    console.log(`🚀 [${session.sessionId}] Starting headless command execution via PTY (isRunning set to true)`);
    
    // Build command with proper arguments
    // Use environment variable if set, otherwise default to 'claude' (not 'claude-cli')
    const claudeBin = process.env.CLAUDE_HEADLESS_BIN || 'claude';
    const terminalType = session.terminalType === 'cursor' ? 'cursor-agent' : claudeBin;
    const currentCliSessionId = session.headless?.cliSessionId;
    
    let commandLine: string;
    
    if (session.terminalType === 'cursor') {
      // Cursor Agent format: cursor-agent --output-format stream-json --print [--resume <session_id>] "prompt"
      commandLine = `cursor-agent --output-format stream-json --print`;
      if (currentCliSessionId) {
        commandLine += ` --resume ${currentCliSessionId}`;
        console.log(`🔄 [${session.sessionId}] Using existing CLI session_id: ${currentCliSessionId}`);
      } else {
        console.log(`🆕 [${session.sessionId}] Starting new CLI session (no existing session_id)`);
      }
      // Escape prompt for shell using single quotes (safer for shell escaping)
      const escapedPrompt = prompt.replace(/'/g, "'\\''");
      commandLine += ` '${escapedPrompt}'\r`;
    } else {
      // Claude CLI format: claude --verbose --print -p "prompt" --output-format stream-json [--session-id <session_id>]
      // Note: --verbose is required for --output-format to work properly
      // Note: --print is required for --output-format to work
      // Note: -p flag must come before --output-format
      const escapedPrompt = prompt.replace(/'/g, "'\\''");
      commandLine = `claude --verbose --print -p '${escapedPrompt}' --output-format stream-json`;
      if (currentCliSessionId) {
        commandLine += ` --session-id ${currentCliSessionId}`;
        console.log(`🔄 [${session.sessionId}] Using existing CLI session_id: ${currentCliSessionId}`);
      } else {
        console.log(`🆕 [${session.sessionId}] Starting new CLI session (no existing session_id)`);
      }
      commandLine += `\r`;
    }
    
    // Write command to PTY - shell will execute it
    if (session.pty) {
      session.pty.write(commandLine);
      console.log(`📝 [${session.sessionId}] Wrote command to PTY: ${commandLine.trim()}`);
    } else {
      throw new Error('PTY not available for headless terminal');
    }
    
    this.notifyHeadlessCommand(session, prompt);
    
    // Mark command as started - completion will be detected from PTY output
    // We'll detect completion by looking for result messages or timeout
    // For now, just mark as started and let pty.onData handle the output
    
    // Set a timeout to mark command as complete if no result is detected
    // Clear any existing timeout first
    if (session.headless.completionTimeout) {
      clearTimeout(session.headless.completionTimeout);
    }
    
    const completionTimeout = setTimeout(() => {
      if (session.headless?.isRunning) {
        console.log(`⏱️ [${session.sessionId}] Command completion timeout - marking as complete`);
        session.headless.isRunning = false;
        session.headless.completionTimeout = undefined;
        // Completion detection is now handled by RecordingStreamManager via HeadlessOutputProcessor
        // This timeout just unlocks the session for the next command
      }
    }, 60000); // 60 second timeout
    
    // Store timeout to clear it if command completes earlier
    session.headless.completionTimeout = completionTimeout;

    return 'Headless command started';
  }
  
  private notifyHeadlessCommand(session: TerminalSession, command: string): void {
    // Store command in input buffer for history
    session.inputBuffer.push(command);
    if (session.inputBuffer.length > 1000) {
      session.inputBuffer.shift();
    }
    
    // Notify global input listeners (for recording stream)
    const normalized = `${command}\r`;
    this.globalInputListeners.forEach(listener => {
      try {
        listener(session, normalized);
      } catch (error) {
        console.error('❌ Global input listener error:', error);
      }
    });
  }

  /**
   * Update headless session CLI session_id (called from RecordingStreamManager)
   */
  updateHeadlessSessionId(sessionId: string, cliSessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (session?.headless) {
      const previousSessionId = session.headless.cliSessionId;
      if (previousSessionId !== cliSessionId) {
        session.headless.cliSessionId = cliSessionId;
        console.log(`💾 [${sessionId}] Updated CLI session_id: ${cliSessionId}`);
      }
    }
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
    
    // For headless terminals, return combined input/output history
    if (this.isHeadlessTerminal(session.terminalType)) {
      // Output buffer already contains commands with prompts, so just join it
      return session.outputBuffer.join('');
    }
    
    // For regular terminals, join as-is (may contain ANSI codes)
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
  
  async destroySession(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (session) {
      // Clear headless command timeout if exists
      if (session.headless?.completionTimeout) {
        clearTimeout(session.headless.completionTimeout);
        session.headless.completionTimeout = undefined;
      }
      
      // Kill all processes in the process group (graceful shutdown)
      await this.killSessionProcesses(session);
      
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
  
  async cleanup(): Promise<void> {
    const cleanupPromises: Promise<void>[] = [];
    
    this.sessions.forEach((session) => {
      // Clear headless command timeouts
      if (session.headless?.completionTimeout) {
        clearTimeout(session.headless.completionTimeout);
        session.headless.completionTimeout = undefined;
      }
      
      // Kill all processes in the process group
      cleanupPromises.push(this.killSessionProcesses(session));
    });
    
    // Wait for all cleanup operations to complete (with timeout)
    await Promise.allSettled(cleanupPromises);
    
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
    return type === 'cursor' || type === 'claude';
  }

  /**
   * Create PTY with interactive shell (unified for all terminal types)
   */
  private createPTY(cwd: string): IPty {
    const shell = process.env.SHELL || (os.platform() === 'win32' ? 'powershell.exe' : 'bash');
    
    // Configure environment
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
    
    return spawn(shell, shellArgs, {
      name: 'xterm-256color',
      cols: 80,
      rows: 30,
      cwd,
      env
    });
  }

  /**
   * Setup unified output handler for PTY (same for all terminal types)
   */
  private setupPTYOutputHandler(session: TerminalSession): void {
    if (!session.pty) {
      return;
    }

    session.pty.onData((data) => {
      session.outputBuffer.push(data);
      
      // Keep only last 10000 lines for history
      if (session.outputBuffer.length > 10000) {
        session.outputBuffer.shift();
      }

      // Send raw output to global listeners (RecordingStreamManager)
      // RecordingStreamManager handles filtering for headless terminals and collects responses for SSE
      this.globalOutputListeners.forEach(listener => {
        try {
          listener(session, data);
        } catch (error) {
          console.error('❌ Global output listener error:', error);
        }
      });

      // Send to terminal display for ALL terminal types
      // RecordingStreamManager will also send filtered output for headless terminals
      if (this.outputRouter) {
        this.outputRouter.routeOutput({
          sessionId: session.sessionId,
          data: data,
          destination: 'terminal_display'
        });
      } else if (this.tunnelClient) {
        // Fallback to direct tunnel client if OutputRouter not set
        this.tunnelClient.sendTerminalOutput(session.sessionId, data);
      }
      
      // Notify WebSocket listeners
      const listeners = this.outputListeners.get(session.sessionId);
      if (listeners) {
        listeners.forEach(listener => listener(data));
      }
    });
  }
  
  /**
   * Get process group ID for a given process ID (Unix only)
   * For shell processes spawned via PTY, the PID is typically the process group leader,
   * so the process group ID equals the PID.
   */
  private getProcessGroupId(pid: number): number {
    if (os.platform() === 'win32') {
      // Windows doesn't have process groups in the same way
      return pid;
    }
    
    try {
      // Try to get process group ID using ps command
      const result = execSync(`ps -o pgid= -p ${pid} 2>/dev/null`, { encoding: 'utf-8' });
      const pgid = parseInt(result.trim(), 10);
      if (!isNaN(pgid) && pgid > 0) {
        return pgid;
      }
    } catch (error) {
      // ps command failed, fall through to fallback
    }
    
    // Fallback: For shell processes, PID is typically the process group leader
    // This is the default behavior for interactive shells spawned via PTY
    return pid;
  }
  
  /**
   * Kill all processes in a session's process group (graceful shutdown with force-kill fallback)
   */
  private async killSessionProcesses(session: TerminalSession): Promise<void> {
    if (!session.pty) {
      return;
    }
    
    const pid = session.pid || session.pty.pid;
    const pgid = session.processGroupId || pid;
    
    if (!pid) {
      console.warn(`⚠️  [${session.sessionId}] No PID available for session`);
      return;
    }
    
    try {
      if (os.platform() === 'win32') {
        // Windows: kill the main process (Windows doesn't have process groups)
        // node-pty's kill() should handle child processes on Windows
        try {
          session.pty.kill();
        } catch (error) {
          // Process may already be dead
          console.warn(`⚠️  [${session.sessionId}] Failed to kill PTY process: ${error}`);
        }
      } else {
        // Unix: kill the entire process group
        // First, try graceful shutdown with SIGTERM
        try {
          // Negative PID means process group
          process.kill(-pgid, 'SIGTERM');
          console.log(`🛑 [${session.sessionId}] Sent SIGTERM to process group ${pgid}`);
        } catch (error: any) {
          // Process group may not exist (already terminated)
          if (error.code !== 'ESRCH') {
            console.warn(`⚠️  [${session.sessionId}] Failed to send SIGTERM to process group ${pgid}: ${error.message}`);
          }
        }
        
        // Wait up to 2 seconds for processes to terminate gracefully
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Check if process still exists and force kill if necessary
        try {
          // Try to send SIGKILL to process group
          process.kill(-pgid, 'SIGKILL');
          console.log(`💀 [${session.sessionId}] Sent SIGKILL to process group ${pgid}`);
        } catch (error: any) {
          // Process group may not exist (already terminated)
          if (error.code !== 'ESRCH') {
            console.warn(`⚠️  [${session.sessionId}] Failed to send SIGKILL to process group ${pgid}: ${error.message}`);
          }
        }
        
        // Also kill the PTY process directly as a fallback
        try {
          session.pty.kill();
        } catch (error) {
          // Process may already be dead
          console.warn(`⚠️  [${session.sessionId}] Failed to kill PTY process: ${error}`);
        }
      }
    } catch (error) {
      console.error(`❌ [${session.sessionId}] Error during process cleanup: ${error}`);
    }
  }
  
}

export type { TerminalType };
