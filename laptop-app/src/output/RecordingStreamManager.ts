import { TerminalManager } from '../terminal/TerminalManager.js';
import type { TunnelClient } from '../tunnel/TunnelClient.js';
import { TerminalScreenEmulator } from './TerminalScreenEmulator.js';
import { TerminalOutputProcessor } from './TerminalOutputProcessor.js';
import { RecordingOutputProcessor, RecordingProcessResult } from './RecordingOutputProcessor.js';

interface SessionState {
  emulator: TerminalScreenEmulator;
  outputProcessor: TerminalOutputProcessor;
  recordingProcessor: RecordingOutputProcessor;
  hasBroadcast: boolean;
  pendingInput: string;
}

type TunnelClientResolver = () => TunnelClient | null;

export class RecordingStreamManager {
  private sessionStates = new Map<string, SessionState>();

  constructor(
    terminalManager: TerminalManager,
    private readonly tunnelClientResolver: TunnelClientResolver
  ) {
    terminalManager.addGlobalOutputListener((session, data) => {
      this.handleTerminalOutput(session.sessionId, session.terminalType, data);
    });

    terminalManager.addGlobalInputListener((session, data) => {
      this.handleTerminalInput(session.sessionId, data);
    });

    terminalManager.addSessionDestroyedListener((sessionId) => {
      this.sessionStates.delete(sessionId);
    });
  }

  private getSessionState(sessionId: string): SessionState {
    let state = this.sessionStates.get(sessionId);
    if (!state) {
      state = {
        emulator: new TerminalScreenEmulator(),
        outputProcessor: new TerminalOutputProcessor(),
        recordingProcessor: new RecordingOutputProcessor(),
        hasBroadcast: false,
        pendingInput: ''
      };
      this.sessionStates.set(sessionId, state);
    }
    return state;
  }

  private handleTerminalInput(sessionId: string, data: string): void {
    if (!data) {
      return;
    }

    const state = this.getSessionState(sessionId);
    state.pendingInput += data;

    if (!/[\r\n]/.test(data)) {
      return;
    }

    const normalized = state.pendingInput.replace(/\r/g, '\n');
    const parts = normalized.split('\n');
    state.pendingInput = parts.pop() ?? '';
    const commands = parts.map((part) => part.trim()).filter((part) => part.length > 0);
    if (commands.length === 0) {
      return;
    }

    // Reset processors and emulator so each new recording starts fresh
    state.outputProcessor.reset();
    state.recordingProcessor.reset();
    state.emulator = new TerminalScreenEmulator();
    state.hasBroadcast = false;

    const lastCommand = commands[commands.length - 1];
    state.recordingProcessor.setLastCommand(lastCommand);
    console.log(`🎙️ Recording stream: captured command for ${sessionId}: ${lastCommand.slice(0, 120)}`);
  }

  private handleTerminalOutput(sessionId: string, terminalType: 'regular' | 'cursor_agent', data: string): void {
    if (terminalType !== 'cursor_agent') {
      return;
    }

    const state = this.getSessionState(sessionId);
    state.emulator.processOutput(data);
    this.logRawChunk(sessionId, data);

    const screenOutput = state.emulator.getScreenContent();
    const newOutput = state.outputProcessor.extractNewLines(screenOutput);

    let outputToProcess = '';
    if (newOutput.trim().length > 0) {
      outputToProcess = newOutput;
    } else if (!state.hasBroadcast && screenOutput.trim().length > 0) {
      outputToProcess = screenOutput;
    } else {
      outputToProcess = '';
    }

    if (outputToProcess.trim().length === 0) {
      return;
    }

    const result = state.recordingProcessor.processOutput(outputToProcess, screenOutput);
    if (!result) {
      return;
    }

    const wasBroadcast = state.hasBroadcast;
    state.hasBroadcast = true;
    const preview = this.normalizePreview(result.delta);
    if (this.shouldLogPreview(preview, wasBroadcast)) {
      console.log(
        `🎙️ Recording stream update` +
          ` | session=${sessionId}` +
          ` | type=${wasBroadcast ? 'delta' : 'initial'}` +
          ` | full=${result.fullText.length} chars` +
          ` | delta=${result.delta.length} chars` +
          (preview.length > 0 ? ` | preview="${preview}"` : '')
      );
    }
    this.broadcastRecordingOutput(sessionId, result);
  }

  private logRawChunk(sessionId: string, raw: string): void {
    console.log(
      `🎙️ RAW chunk | session=${sessionId} | bytes=${raw.length} | data=${JSON.stringify(raw)}`
    );
  }

  private normalizePreview(text: string): string {
    const collapsed = text.replace(/\s+/g, ' ').trim();
    if (collapsed.length === 0) {
      return '';
    }
    const withoutAnsi = collapsed.replace(/[\u001B\u009B][[\]()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g, '');
    const clipped = withoutAnsi.slice(0, 140);
    return clipped + (withoutAnsi.length > clipped.length ? '…' : '');
  }

  private shouldLogPreview(preview: string, alreadyBroadcast: boolean): boolean {
    if (preview.length === 0) {
      return !alreadyBroadcast;
    }

    const noisePrefixes = ['Composer', 'cursor-agent', 'Cursor Agent', '➜ ~', '% ', ']2;', ']7;'];
    if (noisePrefixes.some(prefix => preview.startsWith(prefix))) {
      return false;
    }

    return true;
  }

  private broadcastRecordingOutput(sessionId: string, result: RecordingProcessResult): void {
    const tunnelClient = this.tunnelClientResolver();
    if (!tunnelClient) {
      console.warn(`⚠️ Recording stream: no tunnel client available for session ${sessionId}`);
      return;
    }

    tunnelClient.sendRecordingOutput(sessionId, {
      text: result.fullText,
      delta: result.delta,
      raw: result.rawFiltered,
      timestamp: Date.now()
    });
  }
}

