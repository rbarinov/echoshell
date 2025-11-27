import { spawn, IPty } from 'node-pty';
import os from 'os';
import fs from 'fs/promises';
import { execSync } from 'child_process';
import type { TunnelClient } from '../tunnel/TunnelClient.js';
import { StateManager, type TerminalSessionState } from '../storage/StateManager.js';

type HeadlessTerminalType = 'cursor_cli' | 'claude_cli';
type TerminalType = 'regular' | 'cursor_agent' | HeadlessTerminalType;

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
  cursorAgentWorkingDir?: string;
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
      cursorAgentWorkingDir: terminalType === 'cursor_agent' ? cwd : undefined,
      headless: this.isHeadlessTerminal(terminalType)
        ? {
            isRunning: false
          }
        : undefined
    };

    if (this.isHeadlessTerminal(terminalType)) {
      // For headless terminals, create an interactive shell process
      // We'll write output to it, but need to prevent shell from executing JSON as commands
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
      
      const pty = spawn(shell, shellArgs, {
        name: 'xterm-256color',
        cols: 80,
        rows: 30,
        cwd,
        env
      });
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
      
      // Keep echo enabled - we want to see commands and output
      // pty.onData will capture everything (commands and output) and send to clients
      // We just need to avoid sending data twice (once directly, once via pty.onData)
      
      // Capture output from shell for display
      // For headless terminals, we need to parse JSON and extract session_id and assistant messages
      pty.onData((data) => {
        session.outputBuffer.push(data);
        
        // Keep only last 10000 lines for history
        if (session.outputBuffer.length > 10000) {
          session.outputBuffer.shift();
        }

        // For headless terminals, filter output BEFORE sending to terminal
        // Only send assistant messages to terminal, not result messages or raw JSON
        if (this.isHeadlessTerminal(terminalType)) {
          // Process data line by line for JSON parsing
          const lines = data.split('\n');
          let terminalOutput = ''; // Accumulate only what should appear in terminal
          
          for (const line of lines) {
            const trimmedLine = line.trim();
            if (!trimmedLine) {
              // Keep empty lines for formatting
              terminalOutput += '\n';
              continue;
            }
            
            // Try to extract session_id
            const sessionId = this.extractSessionIdFromLine(trimmedLine, terminalType);
            if (sessionId && session.headless) {
              const previousSessionId = session.headless.cliSessionId;
              if (previousSessionId !== sessionId) {
                session.headless.cliSessionId = sessionId;
                console.log(`💾 [${session.sessionId}] Extracted and stored session_id from PTY output: ${sessionId}`);
              }
            }
            
            // Check for result message FIRST - don't send to terminal
            if (this.isResultMessage(trimmedLine, terminalType)) {
              console.log(`✅ [${session.sessionId}] Detected result message - command completed`);
              
              // Always mark as not running and send completion signal, even if already marked
              if (session.headless) {
                session.headless.isRunning = false;
                session.headless.lastResultSeen = true;
                // Clear completion timeout if exists
                if (session.headless.completionTimeout) {
                  clearTimeout(session.headless.completionTimeout);
                  session.headless.completionTimeout = undefined;
                }
              }
              
              // Don't send result message to terminal - skip it completely
              // Only send completion marker to recording stream for TTS
              console.log(`📤 [${session.sessionId}] Sending [COMMAND_COMPLETE] marker to recording stream`);
              this.emitHeadlessOutput(session, '[COMMAND_COMPLETE]');
              
              // Skip this line - don't add to terminal output
              continue;
            }
            
            // Try to extract assistant message text (only for assistant type, not result)
            const text = this.extractAssistantTextFromLine(trimmedLine, terminalType);
            if (text) {
              console.log(`🎙️ [${session.sessionId}] Extracted assistant text from PTY: ${text.substring(0, 100)}...`);
              // Add assistant text to terminal output (formatted nicely)
              terminalOutput += text + '\n';
              // Also send to recording stream (will be accumulated in handleHeadlessOutput)
              this.emitHeadlessOutput(session, text);
            } else {
              // If it's not a result message and not an assistant message, it might be raw JSON
              // Check if it's JSON - if so, don't send to terminal
              try {
                JSON.parse(trimmedLine);
                // It's JSON but not result/assistant - skip it (might be thinking, system, etc.)
                console.log(`🔇 [${session.sessionId}] Skipping non-assistant JSON message from terminal output`);
                continue;
              } catch (e) {
                // Not JSON - might be shell output or prompt, include it
                terminalOutput += line + '\n';
              }
            }
          }
          
          // Send filtered output to terminal (only assistant messages, no JSON)
          if (terminalOutput.trim().length > 0) {
            if (this.tunnelClient) {
              this.tunnelClient.sendTerminalOutput(session.sessionId, terminalOutput);
            }
            
            const listeners = this.outputListeners.get(session.sessionId);
            if (listeners) {
              listeners.forEach(listener => listener(terminalOutput));
            }
          }
        } else {
          // For regular terminals, send all output as-is
          if (this.tunnelClient) {
            this.tunnelClient.sendTerminalOutput(session.sessionId, data);
          }
          
          const listeners = this.outputListeners.get(session.sessionId);
          if (listeners) {
            listeners.forEach(listener => listener(data));
          }
          
          // Send all output to global listeners
          this.globalOutputListeners.forEach(listener => {
            try {
              listener(session, data);
            } catch (error) {
              console.error('❌ Global output listener error:', error);
            }
          });
        }
      });
      
      this.sessions.set(sessionId, session);
      await this.saveSessionsState();
      console.log(`✅ Created headless session: ${sessionId} (${terminalType}) in ${cwd} with interactive shell`);
      return { sessionId, workingDir: cwd, terminalType, name };
    }

    // Create direct PTY session
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
    const terminalType = session.terminalType === 'cursor_cli' ? 'cursor-agent' : claudeBin;
    const currentCliSessionId = session.headless?.cliSessionId;
    
    // Build command line with --resume if we have session_id (for cursor-agent)
    // For claude, use --session-id instead
    let commandLine = `${terminalType} --output-format stream-json --print`;
    if (currentCliSessionId) {
      if (session.terminalType === 'cursor_cli') {
        commandLine += ` --resume ${currentCliSessionId}`;
      } else {
        commandLine += ` --session-id ${currentCliSessionId}`;
      }
      console.log(`🔄 [${session.sessionId}] Using existing CLI session_id: ${currentCliSessionId}`);
    } else {
      console.log(`🆕 [${session.sessionId}] Starting new CLI session (no existing session_id)`);
    }
    
    // Escape prompt for shell (escape backslashes and quotes, wrap in double quotes)
    const escapedPrompt = prompt.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    commandLine += ` "${escapedPrompt}"\n`;
    
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
        // Send completion message to clients
        // Don't send completion message to terminal display - it's only for recording stream
        // The completion is already handled via [COMMAND_COMPLETE] marker for recording stream
        // This prevents "Command completed" from appearing in terminal output
        // Send completion marker for recording stream
        this.emitHeadlessOutput(session, '\n\n[COMMAND_COMPLETE]');
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

  private emitHeadlessOutput(session: TerminalSession, data: string): void {
    const text = data?.trim();
    if (!text) {
      console.warn(`⚠️ [${session.sessionId}] emitHeadlessOutput: empty text, skipping`);
      return;
    }

    // Don't write to PTY here - this is filtered output for Record view only
    // Raw output (including assistant messages) is already sent via onRawOutput
    // Writing here would cause shell to try to execute the text as commands

    // Notify global output listeners (for recording stream)
    // This handles the filtered output for Record view (watch/phone)
    console.log(`📡 [${session.sessionId}] emitHeadlessOutput: "${text.substring(0, 50)}${text.length > 50 ? '...' : ''}" to ${this.globalOutputListeners.size} listeners`);
    this.globalOutputListeners.forEach(listener => {
      try {
        listener(session, text);
      } catch (error) {
        console.error(`❌ [${session.sessionId}] Global output listener error:`, error);
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
    return type === 'cursor_cli' || type === 'claude_cli';
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
  
  // Extract session_id from JSON line (for headless terminals)
  private extractSessionIdFromLine(line: string, terminalType: TerminalType): string | null {
    if (!line || line.trim().length === 0) {
      return null;
    }

    try {
      const payload = JSON.parse(line);
      if (!payload || typeof payload !== 'object') {
        return null;
      }

      // Try to find session_id in various places
      const candidates = [
        payload.session_id,
        payload.sessionId,
        payload.message?.session_id,
        payload.message?.sessionId,
        payload.result?.session_id,
        payload.result?.sessionId
      ];

      for (const candidate of candidates) {
        if (typeof candidate === 'string' && candidate.trim().length > 0) {
          const sessionId = candidate.trim();
          if (payload.type === 'system' && payload.subtype === 'init') {
            console.log(`🔍 [${terminalType}] Extracted session_id from system/init: ${sessionId}`);
          }
          return sessionId;
        }
      }

      return null;
    } catch (error) {
      // Not JSON, skip silently
      return null;
    }
  }
  
  // Extract assistant text from JSON line (for headless terminals)
  private extractAssistantTextFromLine(line: string, _terminalType: TerminalType): string | null {
    if (!line || line.trim().length === 0) {
      return null;
    }

    try {
      const payload = JSON.parse(line);
      if (!payload || typeof payload !== 'object') {
        return null;
      }

      // Only extract assistant messages (type: "assistant" with message.content)
      if (payload.type === 'assistant' && payload.message?.content) {
        interface ContentBlock {
          type?: string;
          text?: string;
        }
        const parts = Array.isArray(payload.message.content)
          ? payload.message.content
              .map((block: ContentBlock) => {
                if (block.type === 'text' && block.text) {
                  return block.text;
                }
                return null;
              })
              .filter((text: string | null): text is string => text !== null)
          : [];

        if (parts.length > 0) {
          return parts.join('\n');
        }
      }

      return null;
    } catch (error) {
      // Not JSON, skip silently
      return null;
    }
  }
  
  // Check if line is a result message (indicates command completion)
  private isResultMessage(line: string, _terminalType: TerminalType): boolean {
    if (!line || line.trim().length === 0) {
      return false;
    }

    try {
      const payload = JSON.parse(line);
      if (!payload || typeof payload !== 'object') {
        return false;
      }

      // Check for result message type
      return payload.type === 'result' && payload.subtype === 'success';
    } catch (error) {
      // Not JSON, skip silently
      return false;
    }
  }
}

export type { TerminalType };
