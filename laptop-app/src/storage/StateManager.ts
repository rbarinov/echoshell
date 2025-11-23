import fs from 'fs/promises';
import path from 'path';
import os from 'os';

interface TunnelState {
  tunnelId: string;
  apiKey: string;
  publicUrl: string;
  wsUrl: string;
  createdAt: number;
  laptopName: string;
}

interface TerminalSessionState {
  sessionId: string;
  workingDir: string;
  createdAt: number;
}

interface AppState {
  tunnel: TunnelState | null;
  sessions: TerminalSessionState[];
  lastUpdated: number;
}

export class StateManager {
  private stateDir: string;
  private stateFile: string;

  constructor() {
    this.stateDir = path.join(os.homedir(), '.echoshell');
    this.stateFile = path.join(this.stateDir, 'state.json');
  }

  async ensureStateDir(): Promise<void> {
    try {
      await fs.mkdir(this.stateDir, { recursive: true });
    } catch (error) {
      console.error('❌ Failed to create state directory:', error);
      throw error;
    }
  }

  async loadState(): Promise<AppState | null> {
    try {
      const data = await fs.readFile(this.stateFile, 'utf-8');
      const state = JSON.parse(data) as AppState;
      console.log(`📂 Loaded app state from: ${this.stateFile}`);
      if (state.tunnel) {
        console.log(`   Tunnel ID: ${state.tunnel.tunnelId}`);
      }
      if (state.sessions && state.sessions.length > 0) {
        console.log(`   Terminal Sessions: ${state.sessions.length}`);
        state.sessions.forEach(s => {
          console.log(`      - ${s.sessionId} (${s.workingDir})`);
        });
      }
      return state;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        console.log('📂 No existing state found');
        return null;
      }
      console.error('❌ Failed to load state:', error);
      return null;
    }
  }

  async saveState(state: AppState): Promise<void> {
    try {
      await this.ensureStateDir();
      await fs.writeFile(
        this.stateFile,
        JSON.stringify(state, null, 2),
        'utf-8'
      );
      console.log(`💾 Saved app state to: ${this.stateFile}`);
      if (state.tunnel) {
        console.log(`   Tunnel ID: ${state.tunnel.tunnelId}`);
      }
      if (state.sessions && state.sessions.length > 0) {
        console.log(`   Terminal Sessions: ${state.sessions.length}`);
      }
    } catch (error) {
      console.error('❌ Failed to save state:', error);
      throw error;
    }
  }

  // Legacy methods for backward compatibility
  async loadTunnelState(): Promise<TunnelState | null> {
    const state = await this.loadState();
    return state?.tunnel || null;
  }

  async saveTunnelState(tunnel: TunnelState): Promise<void> {
    const existingState = await this.loadState();
    await this.saveState({
      tunnel,
      sessions: existingState?.sessions || [],
      lastUpdated: Date.now()
    });
  }

  async saveSessionsState(sessions: TerminalSessionState[]): Promise<void> {
    const existingState = await this.loadState();
    await this.saveState({
      tunnel: existingState?.tunnel || null,
      sessions,
      lastUpdated: Date.now()
    });
  }

  async deleteState(): Promise<void> {
    try {
      await fs.unlink(this.stateFile);
      console.log(`🗑️  Deleted state: ${this.stateFile}`);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        return;
      }
      console.error('❌ Failed to delete state:', error);
    }
  }

  // Keep old method for compatibility
  async deleteTunnelState(): Promise<void> {
    await this.deleteState();
  }

  getStateFilePath(): string {
    return this.stateFile;
  }
}

export type { TunnelState, TerminalSessionState, AppState };
