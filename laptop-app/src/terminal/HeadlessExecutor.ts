import { spawn, ChildProcess } from 'child_process';
import type { HeadlessTerminalType } from './types';

/**
 * Executes headless terminal commands via direct subprocess (no PTY)
 * Handles cursor-agent and claude CLI tools
 */
export class HeadlessExecutor {
  private subprocess: ChildProcess | null = null;
  private cliSessionId: string | null = null;
  private workingDir: string;
  private terminalType: HeadlessTerminalType;
  private stdoutCallbacks: Set<(data: string) => void> = new Set();
  private stderrCallbacks: Set<(data: string) => void> = new Set();
  private exitCallbacks: Set<(code: number | null) => void> = new Set();
  private executionTimeoutTimer: NodeJS.Timeout | null = null;
  private readonly EXECUTION_TIMEOUT_MS = 60000; // 60 seconds

  constructor(workingDir: string, terminalType: HeadlessTerminalType) {
    this.workingDir = workingDir;
    this.terminalType = terminalType;
  }

  /**
   * Execute a command via subprocess
   * @param prompt - The user prompt/command to execute
   */
  async execute(prompt: string): Promise<void> {
    // Clear any existing timeout
    this.clearExecutionTimeout();

    // Kill any existing subprocess and wait for it to fully terminate
    // This is critical for Claude CLI which locks sessions
    if (this.subprocess) {
      console.log(`🛑 [HeadlessExecutor] Killing existing subprocess before new execution`);
      const subprocessRef = this.subprocess;
      this.kill();

      // Wait longer for Claude CLI to release the session lock
      // Claude CLI needs more time to clean up session state
      const waitTime = this.terminalType === 'claude' ? 1500 : 500;
      await new Promise(resolve => setTimeout(resolve, waitTime));

      // Force kill if still running (double-check with reference)
      if (subprocessRef && !subprocessRef.killed && subprocessRef.pid) {
        console.log(`💀 [HeadlessExecutor] Force killing stubborn subprocess (PID: ${subprocessRef.pid})`);
        try {
          subprocessRef.kill('SIGKILL');
          // Wait a bit more after force kill
          await new Promise(resolve => setTimeout(resolve, 300));
        } catch (error) {
          console.error(`❌ [HeadlessExecutor] Error force killing:`, error);
        }
      }

      // Clear reference to ensure we don't reuse it
      this.subprocess = null;
    }

    // Build command and arguments
    const { command, args } = this.buildCommand(prompt);

    console.log(`🚀 [HeadlessExecutor] Executing ${this.terminalType} command`);
    console.log(`📂 Working directory: ${this.workingDir}`);
    console.log(`💬 Prompt: ${prompt.substring(0, 100)}${prompt.length > 100 ? '...' : ''}`);

    // Spawn subprocess
    this.subprocess = spawn(command, args, {
      cwd: this.workingDir,
      env: {
        ...process.env,
        // Ensure proper terminal environment
        TERM: 'xterm-256color',
      },
      stdio: ['ignore', 'pipe', 'pipe'], // stdin ignored, stdout/stderr piped
    });

    // Setup stdout handler
    this.subprocess.stdout?.on('data', (data: Buffer) => {
      const text = data.toString();
      this.stdoutCallbacks.forEach(callback => {
        try {
          callback(text);
        } catch (error) {
          console.error('❌ [HeadlessExecutor] Error in stdout callback:', error);
        }
      });
    });

    // Setup stderr handler
    this.subprocess.stderr?.on('data', (data: Buffer) => {
      const text = data.toString();
      this.stderrCallbacks.forEach(callback => {
        try {
          callback(text);
        } catch (error) {
          console.error('❌ [HeadlessExecutor] Error in stderr callback:', error);
        }
      });
    });

    // Setup exit handler
    this.subprocess.on('exit', (code: number | null) => {
      console.log(`✅ [HeadlessExecutor] Process exited with code: ${code}`);

      // Clear timeout on process exit
      this.clearExecutionTimeout();

      this.exitCallbacks.forEach(callback => {
        try {
          callback(code);
        } catch (error) {
          console.error('❌ [HeadlessExecutor] Error in exit callback:', error);
        }
      });
      this.subprocess = null;
    });

    // Setup error handler
    this.subprocess.on('error', (error: Error) => {
      console.error(`❌ [HeadlessExecutor] Process error:`, error);

      // Clear timeout on error
      this.clearExecutionTimeout();

      this.stderrCallbacks.forEach(callback => {
        try {
          callback(`Process error: ${error.message}\n`);
        } catch (err) {
          console.error('❌ [HeadlessExecutor] Error in stderr callback:', err);
        }
      });
    });

    // Start execution timeout timer
    this.startExecutionTimeout();
  }

  /**
   * Build command and arguments for subprocess
   */
  private buildCommand(prompt: string): { command: string; args: string[] } {
    const args: string[] = [];

    if (this.terminalType === 'cursor') {
      // Cursor Agent format: cursor-agent --output-format stream-json --print [--resume <session_id>] "prompt"
      args.push('--output-format', 'stream-json');
      args.push('--print');
      
      if (this.cliSessionId) {
        args.push('--resume', this.cliSessionId);
        console.log(`🔄 [HeadlessExecutor] Using existing CLI session_id: ${this.cliSessionId}`);
      } else {
        console.log(`🆕 [HeadlessExecutor] Starting new CLI session (no existing session_id)`);
      }
      
      // Add prompt as last argument (no escaping needed for subprocess args)
      args.push(prompt);
      
      return { command: 'cursor-agent', args };
    } else {
      // Claude CLI format: claude --verbose --print -p "prompt" --output-format stream-json [--resume <session_id>]
      // Note: --verbose is REQUIRED when using --print with --output-format stream-json
      // --resume is used to continue an existing session, not --session-id
      // --session-id is for creating a new session with a specific ID (must be UUID)
      // --resume is for resuming an existing session by its ID
      args.push('--verbose'); // REQUIRED for --print with --output-format stream-json
      args.push('--print');
      args.push('-p', prompt);
      args.push('--output-format', 'stream-json');
      
      if (this.cliSessionId) {
        // Use --resume to continue existing session (not --session-id)
        args.push('--resume', this.cliSessionId);
        console.log(`🔄 [HeadlessExecutor] Resuming Claude CLI session: ${this.cliSessionId}`);
      } else {
        console.log(`🆕 [HeadlessExecutor] Starting new Claude CLI session (no existing session_id)`);
      }
      
      return { command: 'claude', args };
    }
  }

  /**
   * Set CLI session ID for context preservation
   */
  setCliSessionId(sessionId: string | null): void {
    this.cliSessionId = sessionId;
    if (sessionId) {
      console.log(`💾 [HeadlessExecutor] Stored CLI session_id: ${sessionId}`);
    } else {
      console.log(`🗑️  [HeadlessExecutor] Cleared CLI session_id`);
    }
  }

  /**
   * Get current CLI session ID
   */
  getCliSessionId(): string | null {
    return this.cliSessionId;
  }

  /**
   * Kill the subprocess
   */
  kill(): void {
    if (this.subprocess && !this.subprocess.killed) {
      console.log(`🛑 [HeadlessExecutor] Killing subprocess (PID: ${this.subprocess.pid})`);
      
      const subprocessRef = this.subprocess;
      
      // Try graceful shutdown first
      try {
        subprocessRef.kill('SIGTERM');
        console.log(`📤 [HeadlessExecutor] Sent SIGTERM to process ${subprocessRef.pid}`);
        
        // Wait up to 2 seconds for graceful shutdown
        setTimeout(() => {
          if (subprocessRef && !subprocessRef.killed && subprocessRef.pid) {
            console.log(`💀 [HeadlessExecutor] Process ${subprocessRef.pid} still running, force killing with SIGKILL`);
            try {
              subprocessRef.kill('SIGKILL');
            } catch (error) {
              console.error(`❌ [HeadlessExecutor] Error force killing:`, error);
            }
          }
        }, 2000);
      } catch (error) {
        console.error(`❌ [HeadlessExecutor] Error killing subprocess:`, error);
        // Try force kill as fallback
        try {
          if (subprocessRef && subprocessRef.pid) {
            subprocessRef.kill('SIGKILL');
          }
        } catch (killError) {
          console.error(`❌ [HeadlessExecutor] Error force killing as fallback:`, killError);
        }
      }
      
      // Clear reference immediately to prevent reuse
      this.subprocess = null;
    } else if (this.subprocess) {
      console.log(`✅ [HeadlessExecutor] Subprocess already killed`);
      this.subprocess = null;
    }
  }

  /**
   * Check if subprocess is running
   */
  isRunning(): boolean {
    if (!this.subprocess) {
      return false;
    }
    
    // Check if process is actually still running
    // If killed flag is set, it's definitely not running
    if (this.subprocess.killed) {
      return false;
    }
    
    // If process has no PID, it's not running
    if (!this.subprocess.pid) {
      return false;
    }
    
    // Process exists and hasn't been killed
    return true;
  }

  /**
   * Register callback for stdout data
   */
  onStdout(callback: (data: string) => void): void {
    this.stdoutCallbacks.add(callback);
  }

  /**
   * Unregister stdout callback
   */
  offStdout(callback: (data: string) => void): void {
    this.stdoutCallbacks.delete(callback);
  }

  /**
   * Register callback for stderr data
   */
  onStderr(callback: (data: string) => void): void {
    this.stderrCallbacks.add(callback);
  }

  /**
   * Unregister stderr callback
   */
  offStderr(callback: (data: string) => void): void {
    this.stderrCallbacks.delete(callback);
  }

  /**
   * Register callback for process exit
   */
  onExit(callback: (code: number | null) => void): void {
    this.exitCallbacks.add(callback);
  }

  /**
   * Unregister exit callback
   */
  offExit(callback: (code: number | null) => void): void {
    this.exitCallbacks.delete(callback);
  }

  /**
   * Start execution timeout timer
   * Automatically kills subprocess if execution exceeds timeout
   */
  private startExecutionTimeout(): void {
    this.executionTimeoutTimer = setTimeout(() => {
      console.warn(`⏰ [HeadlessExecutor] Execution timeout (${this.EXECUTION_TIMEOUT_MS}ms), killing subprocess`);

      // Send timeout error to stderr callbacks
      this.stderrCallbacks.forEach(callback => {
        try {
          callback(`ERROR: Execution timeout (${this.EXECUTION_TIMEOUT_MS / 1000}s exceeded)\n`);
        } catch (error) {
          console.error('❌ [HeadlessExecutor] Error in stderr callback:', error);
        }
      });

      // Kill the subprocess
      this.kill();
    }, this.EXECUTION_TIMEOUT_MS);
  }

  /**
   * Clear execution timeout timer
   */
  private clearExecutionTimeout(): void {
    if (this.executionTimeoutTimer) {
      clearTimeout(this.executionTimeoutTimer);
      this.executionTimeoutTimer = null;
    }
  }

  /**
   * Clear execution timeout (public method for external control)
   * Used by TerminalManager when completion is detected
   */
  clearTimeout(): void {
    this.clearExecutionTimeout();
  }

  /**
   * Cleanup all callbacks
   */
  cleanup(): void {
    this.clearExecutionTimeout();
    this.stdoutCallbacks.clear();
    this.stderrCallbacks.clear();
    this.exitCallbacks.clear();
    this.kill();
  }
}
