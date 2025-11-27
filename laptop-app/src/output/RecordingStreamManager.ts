import { TerminalManager, type TerminalType } from '../terminal/TerminalManager';
import type { TunnelClient } from '../tunnel/TunnelClient';
import { TerminalScreenEmulator } from './TerminalScreenEmulator';
import { TerminalOutputProcessor } from './TerminalOutputProcessor';
import { RecordingOutputProcessor, RecordingProcessResult } from './RecordingOutputProcessor';
import { HeadlessOutputProcessor } from './HeadlessOutputProcessor';
import type { OutputRouter } from './OutputRouter';

interface SessionState {
  emulator: TerminalScreenEmulator;
  outputProcessor: TerminalOutputProcessor;
  recordingProcessor: RecordingOutputProcessor;
  hasBroadcast: boolean;
  pendingInput: string;
  headlessFullText: string;
  lastHeadlessDelta: string;
}

type TunnelClientResolver = () => TunnelClient | null;

export class RecordingStreamManager {
  private sessionStates = new Map<string, SessionState>();
  private headlessProcessor = new HeadlessOutputProcessor();

  constructor(
    private terminalManager: TerminalManager,
    private readonly tunnelClientResolver: TunnelClientResolver,
    private outputRouter: OutputRouter
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
        pendingInput: '',
        headlessFullText: '',
        lastHeadlessDelta: ''
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
    state.headlessFullText = '';
    state.lastHeadlessDelta = '';

    const lastCommand = commands[commands.length - 1];
    state.recordingProcessor.setLastCommand(lastCommand);
    console.log(`🎙️ Recording stream: captured command for ${sessionId}: ${lastCommand.slice(0, 120)}`);
  }

  private handleTerminalOutput(sessionId: string, terminalType: TerminalType, data: string): void {
    // For headless terminals (cursor, claude), handle JSON output and collect responses for SSE
    if (terminalType === 'cursor' || terminalType === 'claude') {
      this.handleHeadlessOutput(sessionId, data, terminalType);
      return;
    }

    // For regular terminals, no special processing needed
    // Output is already sent to terminal_display by TerminalManager
    // Recording stream is not used for regular terminals
  }

  private handleHeadlessOutput(sessionId: string, data: string, terminalType: TerminalType): void {
    const state = this.getSessionState(sessionId);
    
    // Process raw output using HeadlessOutputProcessor
    const processed = this.headlessProcessor.processChunk(data, terminalType);
    
    // Update session_id if found
    if (processed.sessionId) {
      this.updateHeadlessSessionId(sessionId, processed.sessionId);
    }
    
    // Handle completion
    if (processed.isComplete) {
      this.handleHeadlessCompletion(sessionId, state);
      return;
    }
    
    // Process assistant messages
    if (processed.assistantMessages.length > 0) {
      for (const message of processed.assistantMessages) {
        this.processAssistantMessage(sessionId, state, message);
      }
    }
    
    // Send filtered output to terminal display (via OutputRouter)
    if (processed.rawOutput.trim().length > 0) {
      this.outputRouter.routeOutput({
        sessionId,
        data: processed.rawOutput,
        destination: 'terminal_display'
      });
    }
  }

  private processAssistantMessage(sessionId: string, state: SessionState, message: string): void {
    // Check for duplicates
    if (state.lastHeadlessDelta === message && message.length > 0) {
      console.log(`⏭️ [${sessionId}] Duplicate assistant message, skipping`);
      return;
    }

    state.lastHeadlessDelta = message;
    
    // Append to accumulated text
    if (message.length > 0) {
      const previousLength = state.headlessFullText.length;
      state.headlessFullText =
        state.headlessFullText.length > 0 
          ? `${state.headlessFullText}\n\n${message}` 
          : message;
      console.log(`📝 [${sessionId}] Appended assistant text: ${previousLength} → ${state.headlessFullText.length} chars`);
    }

    // Broadcast to recording stream (for TTS)
    this.broadcastRecordingOutput(sessionId, {
      fullText: state.headlessFullText,
      delta: message,
      rawFiltered: message,
      isComplete: false
    });
  }

  private handleHeadlessCompletion(sessionId: string, state: SessionState): void {
    console.log(`✅ [${sessionId}] Command completed - sending final output for TTS`);
    
    let fullText = state.headlessFullText || '';
    
    if (fullText.length === 0) {
      console.warn(`⚠️ [${sessionId}] headlessFullText is empty when command completed`);
      const fallbackText = state.lastHeadlessDelta || '';
      if (fallbackText.length > 0) {
        console.log(`✅ [${sessionId}] Using fallback text for completion: ${fallbackText.length} chars`);
        fullText = fallbackText;
      }
    }
    
    // Send completion signal
    this.broadcastRecordingOutput(sessionId, {
      fullText: fullText,
      delta: '',
      rawFiltered: '',
      isComplete: true
    });
    
    // Reset state for next command
    state.lastHeadlessDelta = '';
    // Keep headlessFullText for potential retry or debugging
  }

  private updateHeadlessSessionId(sessionId: string, cliSessionId: string): void {
    this.terminalManager.updateHeadlessSessionId(sessionId, cliSessionId);
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
    // Use OutputRouter instead of direct tunnel client access
    this.outputRouter.routeOutput({
      sessionId,
      data: result.rawFiltered || result.delta,
      destination: 'recording_stream',
      metadata: {
        fullText: result.fullText,
        delta: result.delta,
        isComplete: result.isComplete
      }
    });
  }
}

