/**
 * Agent Event Handler
 * 
 * Processes incoming AgentEvents and orchestrates responses
 */

import { v4 as uuidv4 } from 'uuid';
import {
  AgentEvent,
  AgentEventType,
  CommandTextEvent,
  CommandVoiceEvent,
  ContextResetEvent,
  TranscriptionEvent,
  AssistantMessageEvent,
  TTSAudioEvent,
  CompletionEvent,
  ErrorEvent,
  isCommandTextEvent,
  isCommandVoiceEvent,
  isContextResetEvent
} from '../types/AgentEvent.js';
import logger from '../utils/logger.js';
import { STTService } from '../services/STTService.js';
import { TTSService } from '../services/TTSService.js';
import { AIAgent } from './AIAgent.js';

export type AgentEventEmitter = (event: AgentEvent) => void;

interface AgentContext {
  sessionId: string;
  conversationHistory: Array<{ role: string; content: string }>;
  lastMessageId?: string;
}

export class AgentEventHandler {
  private contexts = new Map<string, AgentContext>();
  private sttService: STTService;
  private ttsService: TTSService;
  // AIAgent not used in current implementation (placeholder response instead)
  // private aiAgent: AIAgent;

  constructor(
    private emit: AgentEventEmitter,
    private openaiApiKey: string
  ) {
    this.sttService = new STTService(openaiApiKey);
    this.ttsService = new TTSService(openaiApiKey);
    // Note: AIAgent needs LLMProvider in production - using placeholder for now
    // this.aiAgent = new AIAgent(llmProvider);
  }

  /**
   * Main entry point for processing incoming events
   */
  async handleEvent(event: AgentEvent): Promise<void> {
    try {
      logger.info('Handling agent event', { type: event.type, sessionId: event.session_id });

      if (isCommandTextEvent(event)) {
        await this.handleCommandText(event);
      } else if (isCommandVoiceEvent(event)) {
        await this.handleCommandVoice(event);
      } else if (isContextResetEvent(event)) {
        await this.handleContextReset(event);
      } else {
        logger.warn('Unknown event type', { type: event.type });
        this.emitError(event.session_id, event.message_id, 'UNKNOWN_EVENT', 'Unknown event type');
      }
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      logger.error('Error handling agent event', error, { event });
      this.emitError(
        event.session_id,
        event.message_id,
        'HANDLER_ERROR',
        error.message
      );
    }
  }

  /**
   * Handle text command
   */
  private async handleCommandText(event: CommandTextEvent): Promise<void> {
    const { session_id, message_id, payload } = event;
    const context = this.getOrCreateContext(session_id);
    
    context.conversationHistory.push({
      role: 'user',
      content: payload.text
    });
    context.lastMessageId = message_id;

    // Execute AI agent
    await this.executeAgent(session_id, message_id, payload.text);
  }

  /**
   * Handle voice command
   */
  private async handleCommandVoice(event: CommandVoiceEvent): Promise<void> {
    const { session_id, message_id, payload } = event;
    
    try {
      // Step 1: Transcribe audio
      logger.info('Transcribing audio', { sessionId: session_id });
      const audioBuffer = Buffer.from(payload.audio_base64, 'base64');
      const transcription = await this.sttService.transcribe(audioBuffer, payload.format);

      // Step 2: Emit transcription event
      this.emitTranscription(session_id, message_id, transcription.text);

      // Step 3: Add to context and execute
      const context = this.getOrCreateContext(session_id);
      context.conversationHistory.push({
        role: 'user',
        content: transcription.text
      });
      context.lastMessageId = message_id;

      await this.executeAgent(session_id, message_id, transcription.text);

    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      logger.error('Voice command processing failed', error, { sessionId: session_id });
      this.emitError(session_id, message_id, 'STT_ERROR', 'Failed to transcribe audio');
    }
  }

  /**
   * Execute AI agent and stream responses
   */
  private async executeAgent(sessionId: string, parentMessageId: string, userInput: string): Promise<void> {
    const context = this.getOrCreateContext(sessionId);
    let accumulatedResponse = '';

    try {
      // For now, use a simple echo response until AIAgent.executeStream is implemented
      // TODO: Implement proper AIAgent.executeStream method
      logger.info('Executing agent (placeholder)', { sessionId, userInput });
      
      const mockResponse = `Received: ${userInput}`;
      accumulatedResponse = mockResponse;
      
      this.emitAssistantMessage(
        sessionId,
        parentMessageId,
        mockResponse,
        true
      );

      // Add assistant response to context
      context.conversationHistory.push({
        role: 'assistant',
        content: accumulatedResponse
      });

      // Generate TTS audio
      await this.generateTTS(sessionId, parentMessageId, accumulatedResponse);

      // Emit completion
      this.emitCompletion(sessionId, parentMessageId, true);

    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      logger.error('Agent execution failed', error, { sessionId });
      this.emitError(sessionId, parentMessageId, 'AGENT_ERROR', 'Failed to execute agent');
      this.emitCompletion(sessionId, parentMessageId, false, error.message);
    }
  }

  /**
   * Generate TTS audio for assistant response
   */
  private async generateTTS(sessionId: string, parentMessageId: string, text: string): Promise<void> {
    try {
      logger.info('Generating TTS', { sessionId, textLength: text.length });
      const audioBuffer = await this.ttsService.synthesize(text);
      const audioBase64 = audioBuffer.toString('base64');

      // Estimate duration (rough: 150 words per minute, 5 chars per word avg)
      const estimatedDurationMs = (text.length / 5 / 150) * 60 * 1000;

      this.emitTTSAudio(sessionId, parentMessageId, audioBase64, estimatedDurationMs, text);
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      logger.error('TTS generation failed', error, { sessionId });
      // Don't fail the whole flow - TTS is optional
    }
  }

  /**
   * Handle context reset
   */
  private async handleContextReset(event: ContextResetEvent): Promise<void> {
    const { session_id } = event;
    logger.info('Resetting context', { sessionId: session_id });
    this.contexts.delete(session_id);
    
    // Emit success completion
    this.emitCompletion(session_id, event.message_id, true, 'Context reset');
  }

  /**
   * Get or create context for session
   */
  private getOrCreateContext(sessionId: string): AgentContext {
    if (!this.contexts.has(sessionId)) {
      this.contexts.set(sessionId, {
        sessionId,
        conversationHistory: []
      });
    }
    return this.contexts.get(sessionId)!;
  }

  // Event emission helpers
  private emitTranscription(sessionId: string, parentId: string, text: string): void {
    const event: TranscriptionEvent = {
      type: AgentEventType.TRANSCRIPTION,
      session_id: sessionId,
      message_id: uuidv4(),
      parent_id: parentId,
      timestamp: Date.now(),
      payload: { text }
    };
    this.emit(event);
  }

  private emitAssistantMessage(
    sessionId: string,
    parentId: string,
    content: string,
    isFinal: boolean,
    metadata?: Record<string, unknown>
  ): void {
    const event: AssistantMessageEvent = {
      type: AgentEventType.ASSISTANT_MESSAGE,
      session_id: sessionId,
      message_id: uuidv4(),
      parent_id: parentId,
      timestamp: Date.now(),
      payload: {
        content,
        is_final: isFinal,
        metadata
      }
    };
    this.emit(event);
  }

  private emitTTSAudio(
    sessionId: string,
    parentId: string,
    audioBase64: string,
    durationMs: number,
    transcript: string
  ): void {
    const event: TTSAudioEvent = {
      type: AgentEventType.TTS_AUDIO,
      session_id: sessionId,
      message_id: uuidv4(),
      parent_id: parentId,
      timestamp: Date.now(),
      payload: {
        audio_base64: audioBase64,
        format: 'mp3',
        duration_ms: durationMs,
        transcript
      }
    };
    this.emit(event);
  }

  private emitCompletion(sessionId: string, parentId: string, success: boolean, result?: string): void {
    const event: CompletionEvent = {
      type: AgentEventType.COMPLETION,
      session_id: sessionId,
      message_id: uuidv4(),
      parent_id: parentId,
      timestamp: Date.now(),
      payload: {
        success,
        result,
        error: success ? undefined : result
      }
    };
    this.emit(event);
  }

  private emitError(sessionId: string, parentId: string, code: string, message: string): void {
    const event: ErrorEvent = {
      type: AgentEventType.ERROR,
      session_id: sessionId,
      message_id: uuidv4(),
      parent_id: parentId,
      timestamp: Date.now(),
      payload: {
        code,
        message
      }
    };
    this.emit(event);
  }
}

