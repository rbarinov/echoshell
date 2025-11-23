import { spawn, IPty } from 'node-pty';
import os from 'os';

interface TerminalSession {
  sessionId: string;
  pty: IPty;
  workingDir: string;
  createdAt: number;
  outputBuffer: string[];
}

export class TerminalManager {
  private sessions = new Map<string, TerminalSession>();
  private outputListeners = new Map<string, Set<(data: string) => void>>();
  
  createSession(workingDir?: string): { sessionId: string; workingDir: string } {
    const sessionId = `session-${Date.now()}`;
    const cwd = workingDir || process.env.HOME || os.homedir();
    
    const shell = process.env.SHELL || (os.platform() === 'win32' ? 'powershell.exe' : 'bash');
    
    const pty = spawn(shell, [], {
      name: 'xterm-color',
      cols: 80,
      rows: 30,
      cwd,
      env: process.env as any
    });
    
    const session: TerminalSession = {
      sessionId,
      pty,
      workingDir: cwd,
      createdAt: Date.now(),
      outputBuffer: []
    };
    
    // Capture output
    pty.onData((data) => {
      session.outputBuffer.push(data);
      
      // Keep only last 1000 lines
      if (session.outputBuffer.length > 1000) {
        session.outputBuffer.shift();
      }
      
      // Notify listeners (for WebSocket streaming)
      const listeners = this.outputListeners.get(sessionId);
      if (listeners) {
        listeners.forEach(listener => listener(data));
      }
    });
    
    this.sessions.set(sessionId, session);
    
    return { sessionId, workingDir: cwd };
  }
  
  executeCommand(sessionId: string, command: string): string {
    const session = this.sessions.get(sessionId);
    
    if (!session) {
      throw new Error('Session not found');
    }
    
    // Clear buffer before command
    session.outputBuffer = [];
    
    // Write command to PTY
    session.pty.write(command + '\r');
    
    // Wait a bit for output (simple approach)
    // In production, you'd want more sophisticated output detection
    return new Promise((resolve) => {
      setTimeout(() => {
        const output = session.outputBuffer.join('');
        resolve(output);
      }, 500);
    }) as any;
  }
  
  listSessions(): Array<{ sessionId: string; workingDir: string }> {
    return Array.from(this.sessions.values()).map(s => ({
      sessionId: s.sessionId,
      workingDir: s.workingDir
    }));
  }
  
  getSession(sessionId: string): TerminalSession | undefined {
    return this.sessions.get(sessionId);
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
      session.pty.kill();
      this.sessions.delete(sessionId);
      this.outputListeners.delete(sessionId);
    }
  }
  
  cleanup(): void {
    this.sessions.forEach((session) => {
      session.pty.kill();
    });
    this.sessions.clear();
    this.outputListeners.clear();
  }
}
