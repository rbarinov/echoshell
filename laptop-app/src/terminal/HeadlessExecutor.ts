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

  constructor(workingDir: string, terminalType: HeadlessTerminalType) {
    this.workingDir = workingDir;
    this.terminalType = terminalType;
  }

  /**
   * Execute a command via subprocess
   * @param prompt - The user prompt/command to execute
   */
  async execute(prompt: string): Promise<void> {
    // Kill any existing subprocess
    if (this.subprocess) {
      this.kill();
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
      this.stderrCallbacks.forEach(callback => {
        try {
          callback(`Process error: ${error.message}\n`);
        } catch (err) {
          console.error('❌ [HeadlessExecutor] Error in stderr callback:', err);
        }
      });
    });
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
      // Claude CLI format: claude --verbose --print -p "prompt" --output-format stream-json [--session-id <session_id>]
      args.push('--verbose');
      args.push('--print');
      args.push('-p', prompt);
      args.push('--output-format', 'stream-json');
      
      if (this.cliSessionId) {
        args.push('--session-id', this.cliSessionId);
        console.log(`🔄 [HeadlessExecutor] Using existing CLI session_id: ${this.cliSessionId}`);
      } else {
        console.log(`🆕 [HeadlessExecutor] Starting new CLI session (no existing session_id)`);
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
    if (this.subprocess) {
      console.log(`🛑 [HeadlessExecutor] Killing subprocess`);
      
      // Try graceful shutdown first
      if (this.subprocess.kill) {
        try {
          this.subprocess.kill('SIGTERM');
          
          // Wait up to 2 seconds for graceful shutdown
          setTimeout(() => {
            if (this.subprocess && !this.subprocess.killed) {
              console.log(`💀 [HeadlessExecutor] Force killing subprocess`);
              this.subprocess.kill('SIGKILL');
            }
          }, 2000);
        } catch (error) {
          console.error(`❌ [HeadlessExecutor] Error killing subprocess:`, error);
        }
      }
      
      this.subprocess = null;
    }
  }

  /**
   * Check if subprocess is running
   */
  isRunning(): boolean {
    return this.subprocess !== null && !this.subprocess.killed;
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
   * Cleanup all callbacks
   */
  cleanup(): void {
    this.stdoutCallbacks.clear();
    this.stderrCallbacks.clear();
    this.exitCallbacks.clear();
    this.kill();
  }
}
