import { TerminalManager, type TerminalType } from '../terminal/TerminalManager';
import type { TunnelClient } from '../tunnel/TunnelClient';
import { TerminalScreenEmulator } from './TerminalScreenEmulator';
import { TerminalOutputProcessor } from './TerminalOutputProcessor';
import { RecordingOutputProcessor, RecordingProcessResult } from './RecordingOutputProcessor';
import { HeadlessOutputProcessor } from './HeadlessOutputProcessor';
import type { OutputRouter } from './OutputRouter';
import type { ChatMessage } from '../terminal/types';

interface SessionState {
  emulator: TerminalScreenEmulator;
  outputProcessor: TerminalOutputProcessor;
  recordingProcessor: RecordingOutputProcessor;
  hasBroadcast: boolean;
  pendingInput: string;
  headlessFullText: string;
  lastHeadlessDelta: string;
  // For new headless architecture (chat messages)
  assistantMessages: ChatMessage[]; // Accumulated assistant messages for current execution
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

    // Listen for chat messages from headless terminals (new architecture)
    terminalManager.addChatMessageListener((sessionId, message, isComplete) => {
      this.handleChatMessage(sessionId, message, isComplete);
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
        lastHeadlessDelta: '',
        assistantMessages: []
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
    state.assistantMessages = []; // Reset assistant messages for new execution

    const lastCommand = commands[commands.length - 1];
    state.recordingProcessor.setLastCommand(lastCommand);
    console.log(`🎙️ Recording stream: captured command for ${sessionId}: ${lastCommand.slice(0, 120)}`);
  }

  private handleTerminalOutput(sessionId: string, terminalType: TerminalType, data: string): void {
    // For headless terminals with new architecture, chat messages are handled separately
    // This method is only called for old PTY-based headless terminals (legacy)
    // New architecture uses chat messages via TerminalManager's chat history
    
    // For regular terminals, no special processing needed
    // Output is already sent to terminal_display by TerminalManager
    // Recording stream is not used for regular terminals
  }

  /**
   * Handle chat message from headless terminal (new architecture)
   * Called when a chat message is received via OutputRouter
   */
  handleChatMessage(sessionId: string, message: ChatMessage, isComplete: boolean): void {
    const session = this.terminalManager.getSession(sessionId);
    if (!session || !this.isHeadlessTerminal(session.terminalType)) {
      return; // Not a headless terminal or session not found
    }

    const state = this.getSessionState(sessionId);

    // Only accumulate assistant messages for TTS
    if (message.type === 'assistant') {
      state.assistantMessages.push(message);
      console.log(`📝 [${sessionId}] Accumulated assistant message: ${message.content.substring(0, 100)}...`);
    }

    // If execution is complete, send tts_ready event
    if (isComplete) {
      this.sendTTSReady(sessionId, state);
    }
  }

  /**
   * Send tts_ready event with accumulated assistant messages
   * Extracts text content suitable for TTS - removes code blocks and thinking, but preserves inline terms
   * Also saves a tts_audio message to chat history for voice message bubbles
   */
  private sendTTSReady(sessionId: string, state: SessionState): void {
    // Extract TTS-friendly content from assistant messages
    const assistantTexts = state.assistantMessages
      .map(msg => {
        // Start with message content
        let text = msg.content || '';

        // Remove thinking/metadata content (if present in content)
        // Thinking is usually in metadata, but check content too
        if (msg.metadata?.thinking) {
          // Skip thinking - it's internal reasoning, not for TTS
        }

        // Remove code blocks (```language\ncode\n```)
        // These are usually long and not suitable for TTS
        text = text.replace(/```[\s\S]*?```/g, '');

        // IMPORTANT: Keep inline code (`term`) - these are often technical terms
        // Just remove the backticks for natural TTS reading
        text = text.replace(/`([^`]+)`/g, '$1');

        // Remove markdown links [text](url) - keep only text
        text = text.replace(/\[([^\]]+)\]\([^\)]+\)/g, '$1');

        // Remove markdown headers (# Header) - but keep the text
        text = text.replace(/^#{1,6}\s+/gm, '');

        // Remove markdown bold/italic (**text** or *text*) - but keep the text
        text = text.replace(/\*\*([^\*]+)\*\*/g, '$1');
        text = text.replace(/\*([^\*]+)\*/g, '$1');

        // Remove markdown list markers but keep content
        text = text.replace(/^[\s]*[-*+]\s+/gm, '');
        text = text.replace(/^[\s]*\d+\.\s+/gm, '');

        // Remove markdown blockquotes (> text) - but keep the text
        text = text.replace(/^>\s+/gm, '');

        // Remove markdown horizontal rules (--- or ***)
        text = text.replace(/^[-*]{3,}$/gm, '');

        // Clean up extra whitespace and newlines
        text = text.replace(/\n{3,}/g, '\n\n'); // Max 2 newlines
        text = text.replace(/\s+/g, ' '); // Multiple spaces to single
        text = text.trim();

        return text;
      })
      .filter(text => text.length > 0);

    const combinedText = assistantTexts.join('\n\n');

    if (combinedText.length === 0) {
      console.warn(`⚠️ [${sessionId}] No assistant text to send for TTS (all content was code/formatting)`);
      return;
    }

    console.log(`🎙️ [${sessionId}] Sending tts_ready with ${assistantTexts.length} assistant messages (${combinedText.length} chars, dry summary)`);

    // Save tts_audio message to chat history (for voice message bubbles)
    // This allows showing voice messages when user returns to chat
    const ttsAudioMessage: ChatMessage = {
      id: `tts-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      timestamp: Date.now(),
      type: 'tts_audio',
      content: '🔊 Voice response', // Display text for the bubble
      metadata: {
        ttsText: combinedText // The actual text that was synthesized
      }
    };

    // Add to chat history via TerminalManager
    const session = this.terminalManager.getSession(sessionId);
    if (session?.chatHistory) {
      this.terminalManager.addMessage(sessionId, ttsAudioMessage);
      console.log(`💾 [${sessionId}] Saved tts_audio message to chat history`);
    }

    // Send tts_audio message to iOS via WebSocket (so it appears in chat)
    this.outputRouter.sendChatMessage(sessionId, ttsAudioMessage);
    console.log(`📤 [${sessionId}] Sent tts_audio message to iOS via WebSocket`);

    // Send tts_ready event via OutputRouter (for TTS synthesis)
    this.outputRouter.routeOutput({
      sessionId,
      data: combinedText,
      destination: 'recording_stream',
      metadata: {
        fullText: combinedText,
        delta: '',
        isComplete: true
      }
    });

    // Reset for next execution
    state.assistantMessages = [];
  }

  private isHeadlessTerminal(type: TerminalType): boolean {
    return type === 'cursor' || type === 'claude';
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

