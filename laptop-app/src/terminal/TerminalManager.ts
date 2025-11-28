import { spawn, IPty } from 'node-pty';
import os from 'os';
import fs from 'fs/promises';
import { execSync } from 'child_process';
import { randomUUID } from 'crypto';
import type { TunnelClient } from '../tunnel/TunnelClient';
import { StateManager, type TerminalSessionState } from '../storage/StateManager';
import type { OutputRouter } from '../output/OutputRouter';
import { HeadlessExecutor } from './HeadlessExecutor';
import { AgentOutputParser } from '../output/AgentOutputParser';
import type {
  TerminalType,
  HeadlessTerminalType,
  ChatHistory,
  ChatMessage,
  CurrentExecution,
} from './types';

interface TerminalSession {
  sessionId: string;
  workingDir: string;
  createdAt: number;
  inputBuffer: string[]; // Store input commands for history
  terminalType: TerminalType;
  name?: string;

  // For regular terminals
  pty?: IPty;
  pid?: number; // Process ID of the PTY process
  processGroupId?: number; // Process group ID for killing all child processes
  outputBuffer?: string[];

  // For headless terminals (NEW)
  executor?: HeadlessExecutor;
  chatHistory?: ChatHistory;
  currentExecution?: CurrentExecution;
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
  private chatMessageListeners = new Set<(sessionId: string, message: ChatMessage, isComplete: boolean) => void>();
  
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
      inputBuffer: [],
      terminalType,
      name,
    };

    if (this.isHeadlessTerminal(terminalType)) {
      // For headless terminals: create HeadlessExecutor and initialize chat history
      const executor = new HeadlessExecutor(cwd, terminalType);
      session.executor = executor;
      
      // Initialize chat history
      session.chatHistory = {
        sessionId,
        messages: [],
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      
      // Initialize current execution state
      session.currentExecution = {
        isRunning: false,
        startedAt: 0,
        currentMessages: [],
      };
      
      // Setup output handlers for headless executor
      this.setupHeadlessOutputHandler(session);
      
      console.log(`🤖 [${sessionId}] Created headless terminal with executor`);
    } else {
      // For regular terminals: create PTY (existing logic)
      session.outputBuffer = [];
      const pty = this.createPTY(cwd, terminalType);
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
      
      // Setup output handler for regular terminal
      this.setupPTYOutputHandler(session);
    }
    
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
    
    if (this.isHeadlessTerminal(session.terminalType)) {
      // For headless terminals, execute command via subprocess (HeadlessExecutor)
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

    if (!session.executor || !session.currentExecution || !session.chatHistory) {
      throw new Error('Headless terminal not properly initialized');
    }

    // Check if already running
    if (session.currentExecution.isRunning) {
      const errorMsg = `Headless session is busy. Please wait for the current command to finish.`;
      console.error(`❌ [${session.sessionId}] ${errorMsg}`);
      throw new Error(errorMsg);
    }

    // Get current CLI session ID from executor
    const currentCliSessionId = session.executor.getCliSessionId();
    console.log(`📋 [${session.sessionId}] Before command execution - CLI session_id: ${currentCliSessionId || 'none'}`);

    // Mark as running
    session.currentExecution.isRunning = true;
    session.currentExecution.startedAt = Date.now();
    session.currentExecution.currentMessages = []; // Clear previous execution messages
    console.log(`🚀 [${session.sessionId}] Starting headless command execution via subprocess`);

    // Create user message and add to chat history
    const userMessage: ChatMessage = {
      id: randomUUID(),
      timestamp: Date.now(),
      type: 'user',
      content: prompt,
    };
    session.chatHistory.messages.push(userMessage);
    session.chatHistory.updatedAt = Date.now();
    session.currentExecution.currentMessages.push(userMessage);

    // Send user message via OutputRouter
    if (this.outputRouter) {
      this.outputRouter.sendChatMessage(session.sessionId, userMessage);
    }

    // Execute command via HeadlessExecutor
    try {
      await session.executor.execute(prompt);
      console.log(`✅ [${session.sessionId}] Command execution started`);
    } catch (error) {
      session.currentExecution.isRunning = false;
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ [${session.sessionId}] Failed to execute command: ${errorMessage}`);
      
      // Create error message
      const errorMsg: ChatMessage = {
        id: randomUUID(),
        timestamp: Date.now(),
        type: 'error',
        content: `Failed to execute command: ${errorMessage}`,
      };
      session.chatHistory.messages.push(errorMsg);
      session.chatHistory.updatedAt = Date.now();
      session.currentExecution.currentMessages.push(errorMsg);
      
      if (this.outputRouter) {
        this.outputRouter.sendChatMessage(session.sessionId, errorMsg);
      }
      
      throw error;
    }

    // Set timeout for completion (60 seconds)
    const completionTimeout = setTimeout(() => {
      if (session.currentExecution?.isRunning) {
        console.log(`⏱️ [${session.sessionId}] Command completion timeout - marking as complete`);
        session.currentExecution.isRunning = false;
      }
    }, 60000);

    // Store timeout reference (we'll clear it on completion)
    // Note: We don't store it in session anymore, just let it run

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
    if (session?.executor) {
      const previousSessionId = session.executor.getCliSessionId();
      if (previousSessionId !== cliSessionId) {
        session.executor.setCliSessionId(cliSessionId);
        if (session.currentExecution) {
          session.currentExecution.cliSessionId = cliSessionId;
        }
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
  
  getHistory(sessionId: string): string {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return '';
    }
    
    // For headless terminals, return chat history as text
    if (this.isHeadlessTerminal(session.terminalType) && session.chatHistory) {
      return session.chatHistory.messages
        .map(msg => `${msg.type}: ${msg.content}`)
        .join('\n');
    }
    
    // For regular terminals, join output buffer (may contain ANSI codes)
    return session.outputBuffer?.join('') || '';
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
      // For headless terminals, cleanup executor
      if (session.executor) {
        session.executor.cleanup();
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
      // For headless terminals, cleanup executor
      if (session.executor) {
        session.executor.cleanup();
      }
      
      // Kill all processes in the process group (for regular terminals)
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

  addChatMessageListener(listener: (sessionId: string, message: ChatMessage, isComplete: boolean) => void): void {
    this.chatMessageListeners.add(listener);
  }

  getSession(sessionId: string): TerminalSession | undefined {
    return this.sessions.get(sessionId);
  }

  private isHeadlessTerminal(type: TerminalType): type is HeadlessTerminalType {
    return type === 'cursor' || type === 'claude';
  }

  /**
   * Create PTY with interactive shell (unified for all terminal types)
   */
  private createPTY(cwd: string, terminalType?: TerminalType): IPty {
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

    // For headless terminals, start shell with echo disabled from the beginning
    // This prevents duplicate character display when using cursor-agent or claude-cli
    if (terminalType && this.isHeadlessTerminal(terminalType)) {
      if (shell.includes('zsh')) {
        // For zsh: use -c to run command that disables echo, then starts interactive shell
        shellArgs.push('-c', 'stty -echo; exec zsh -i');
      } else if (shell.includes('bash')) {
        // For bash: use -c to run command that disables echo, then starts interactive shell
        shellArgs.push('-c', 'stty -echo; exec bash -i');
      }
      console.log(`🔇 Creating headless terminal (${terminalType}) with echo disabled from start`);
    } else {
      // For regular terminals, use normal interactive mode with echo
      if (shell.includes('zsh')) {
        shellArgs.push('-i');
      } else if (shell.includes('bash')) {
        shellArgs.push('-i');
      }
    }

    const pty = spawn(shell, shellArgs, {
      name: 'xterm-256color',
      cols: 80,
      rows: 30,
      cwd,
      env
    });

    return pty;
  }

  /**
   * Setup unified output handler for PTY (same for all terminal types)
   */
  private setupPTYOutputHandler(session: TerminalSession): void {
    if (!session.pty) {
      return;
    }

    session.pty.onData((data) => {
      if (!session.outputBuffer) {
        session.outputBuffer = [];
      }
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
   * Setup output handler for headless terminals (subprocess-based)
   */
  private setupHeadlessOutputHandler(session: TerminalSession): void {
    if (!session.executor || !this.isHeadlessTerminal(session.terminalType)) {
      return;
    }

    const parser = new AgentOutputParser();
    let buffer = '';

    // Handle stdout (JSON stream)
    session.executor.onStdout((data: string) => {
      buffer += data;
      
      // Process complete lines
      const lines = buffer.split('\n');
      buffer = lines.pop() || ''; // Keep incomplete line in buffer

      for (const line of lines) {
        if (!line.trim()) continue;

        const parsed = parser.parseLine(line);
        
        // Update session_id if found
        if (parsed.sessionId && session.executor) {
          session.executor.setCliSessionId(parsed.sessionId);
          if (session.currentExecution) {
            session.currentExecution.cliSessionId = parsed.sessionId;
          }
        }

        // Handle completion
        if (parsed.isComplete) {
          if (session.currentExecution) {
            session.currentExecution.isRunning = false;
          }
          
          // Notify chat message listeners about completion (for RecordingStreamManager)
          // Send a completion signal with the last message if available
          const lastMessage = session.currentExecution?.currentMessages[session.currentExecution.currentMessages.length - 1];
          if (lastMessage) {
            this.chatMessageListeners.forEach(listener => {
              try {
                listener(session.sessionId, lastMessage, true);
              } catch (error) {
                console.error('❌ Chat message listener error:', error);
              }
            });
          }
          continue;
        }

        // Handle chat message
        if (parsed.message) {
          // Add to current execution messages
          if (session.currentExecution) {
            session.currentExecution.currentMessages.push(parsed.message);
          }

          // Add to chat history
          if (session.chatHistory) {
            session.chatHistory.messages.push(parsed.message);
            session.chatHistory.updatedAt = Date.now();
          }

          // Send chat message via OutputRouter
          if (this.outputRouter) {
            // OutputRouter will handle chat_message format
            this.outputRouter.sendChatMessage(session.sessionId, parsed.message);
          }

          // Notify chat message listeners (for RecordingStreamManager)
          if (parsed.message) {
            this.chatMessageListeners.forEach(listener => {
              try {
                listener(session.sessionId, parsed.message!, false);
              } catch (error) {
                console.error('❌ Chat message listener error:', error);
              }
            });
          }
        }
      }
    });

    // Handle stderr (errors)
    session.executor.onStderr((data: string) => {
      console.error(`❌ [${session.sessionId}] Headless executor stderr:`, data);
      
      // Create error message
      const errorMessage: ChatMessage = {
        id: randomUUID(),
        timestamp: Date.now(),
        type: 'error',
        content: `Error: ${data.trim()}`,
      };

      // Add to current execution and history
      if (session.currentExecution) {
        session.currentExecution.currentMessages.push(errorMessage);
      }
      if (session.chatHistory) {
        session.chatHistory.messages.push(errorMessage);
        session.chatHistory.updatedAt = Date.now();
      }

      // Send error message
      if (this.outputRouter) {
        this.outputRouter.sendChatMessage(session.sessionId, errorMessage);
      }
    });

    // Handle exit
    session.executor.onExit((code: number | null) => {
      if (session.currentExecution) {
        session.currentExecution.isRunning = false;
      }
      console.log(`✅ [${session.sessionId}] Headless executor exited with code: ${code}`);
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
