import { TerminalManager, type TerminalType } from '../terminal/TerminalManager.js';
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
  headlessFullText: string;
  lastHeadlessDelta: string;
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
    if (terminalType === 'cursor_cli' || terminalType === 'claude_cli') {
      this.handleHeadlessOutput(sessionId, data);
      return;
    }

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

  private handleHeadlessOutput(sessionId: string, data: string): void {
    const text = data?.trim();
    
    // Check if this is a result message (JSON with type: "result")
    let isResultMessage = false;
    let resultText = '';
    try {
      const parsed = JSON.parse(text);
      if (parsed.type === 'result' && parsed.subtype === 'success' && !parsed.is_error) {
        isResultMessage = true;
        resultText = parsed.result || '';
        console.log(`✅✅✅ [${sessionId}] Detected result message in RecordingStreamManager: result=${resultText.length} chars`);
      }
    } catch (e) {
      // Not JSON, continue with normal processing
    }
    
    // Check for completion marker FIRST
    const isComplete = text === '[COMMAND_COMPLETE]' || text.includes('[COMMAND_COMPLETE]') || isResultMessage;
    
    if (isComplete && (text === '[COMMAND_COMPLETE]' || isResultMessage)) {
      // Completion detected - either via marker or result message
      // Send final message with accumulated text and isComplete=true to trigger TTS
      const state = this.getSessionState(sessionId);
      let fullText = state.headlessFullText || '';
      
      // If we got result message with text, prefer it over accumulated text
      if (isResultMessage && resultText.length > 0) {
        console.log(`✅✅✅ [${sessionId}] Result message contains text (${resultText.length} chars), using it as final text`);
        // If accumulated text is empty or result text is different, use result text
        if (fullText.length === 0 || !fullText.includes(resultText.trim())) {
          fullText = resultText.trim();
        }
      }
      
      console.log(`✅✅✅ [${sessionId}] Command completed (${isResultMessage ? 'via result message' : 'via COMMAND_COMPLETE marker'}) - sending final output for TTS: ${fullText.length} chars`);
      console.log(`✅✅✅ [${sessionId}] Full text preview: "${fullText.substring(0, 200)}..."`);
      
      if (fullText.length === 0) {
        console.warn(`⚠️⚠️⚠️ [${sessionId}] WARNING: headlessFullText is empty when command completed!`);
        console.warn(`⚠️⚠️⚠️ [${sessionId}] lastHeadlessDelta: ${state.lastHeadlessDelta.length} chars`);
        // Use lastHeadlessDelta as fallback if headlessFullText is empty
        const fallbackText = state.lastHeadlessDelta || '';
        if (fallbackText.length > 0) {
          console.log(`✅✅✅ [${sessionId}] Using fallback text for completion: ${fallbackText.length} chars`);
          this.broadcastRecordingOutput(sessionId, {
            fullText: fallbackText,
            delta: '',
            rawFiltered: '',
            isComplete: true
          });
        } else {
          // Even if empty, send completion signal so iOS can transition out of waiting state
          console.log(`⚠️⚠️⚠️ [${sessionId}] No text available, sending empty completion signal`);
          this.broadcastRecordingOutput(sessionId, {
            fullText: '',
            delta: '',
            rawFiltered: '',
            isComplete: true
          });
        }
      } else {
        console.log(`✅✅✅ [${sessionId}] Broadcasting completion with fullText: ${fullText.length} chars, isComplete=true`);
        this.broadcastRecordingOutput(sessionId, {
          fullText: fullText,
          delta: '', // No new delta, just completion signal
          rawFiltered: '',
          isComplete: true
        });
      }
      // Reset state for next command
      state.lastHeadlessDelta = '';
      // Don't reset headlessFullText here - keep it for potential retry or debugging
      return;
    }
    
    if (!text || text.length === 0) {
      console.log(`⚠️ [${sessionId}] handleHeadlessOutput: empty text, skipping`);
      return;
    }

    console.log(`📥 [${sessionId}] RecordingStreamManager received headless output: ${text.substring(0, 100)}...`);

    // Remove completion marker if present (shouldn't happen, but just in case)
    // Also skip result messages as they're already handled above
    if (isResultMessage) {
      console.log(`⏭️ [${sessionId}] Skipping result message - already processed as completion`);
      return;
    }
    
    const cleanText = isComplete ? text.replace('[COMMAND_COMPLETE]', '').trim() : text;

    if (cleanText.length === 0 && !isComplete) {
      console.log(`⚠️ [${sessionId}] handleHeadlessOutput: cleanText is empty and not complete, skipping`);
      return;
    }

    const state = this.getSessionState(sessionId);
    
    // For assistant messages, append to accumulated text
    // Check if this is a duplicate delta (skip if same as last)
    if (state.lastHeadlessDelta === cleanText && !isComplete && cleanText.length > 0) {
      console.log(`⏭️ [${sessionId}] handleHeadlessOutput: duplicate delta, skipping`);
      return;
    }

    state.lastHeadlessDelta = cleanText;
    
    // Append assistant text to accumulated full text
    if (cleanText.length > 0) {
      const previousLength = state.headlessFullText.length;
      state.headlessFullText =
        state.headlessFullText.length > 0 ? `${state.headlessFullText}\n\n${cleanText}` : cleanText;
      console.log(`📝 [${sessionId}] Appended assistant text: ${previousLength} → ${state.headlessFullText.length} chars`);
    }

    console.log(`📤 [${sessionId}] Broadcasting recording output: fullText=${state.headlessFullText.length} chars, delta=${cleanText.length} chars, isComplete=${isComplete}`);
    this.broadcastRecordingOutput(sessionId, {
      fullText: state.headlessFullText,
      delta: cleanText,
      rawFiltered: cleanText,
      isComplete: false // Not complete yet, more assistant messages may come
    });
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
      console.warn(`⚠️⚠️⚠️ Recording stream: no tunnel client available for session ${sessionId}`);
      return;
    }

    const message = {
      text: result.fullText,
      delta: result.delta,
      raw: result.rawFiltered,
      timestamp: Date.now(),
      isComplete: result.isComplete || false
    };
    
    console.log(`📤📤📤 [${sessionId}] Broadcasting recording output: text=${message.text.length} chars, delta=${message.delta.length} chars, isComplete=${message.isComplete}`);
    tunnelClient.sendRecordingOutput(sessionId, message);
  }
}

