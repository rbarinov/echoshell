/**
 * Unified Agent Event Protocol
 * 
 * Single schema for ALL communication between iOS ↔ Tunnel Server ↔ Laptop App
 * Replaces fragmented channels (terminal/stream, recording/stream, etc.)
 */

export enum AgentEventType {
  // Client → Server
  COMMAND_TEXT = 'command_text',
  COMMAND_VOICE = 'command_voice',
  CONTEXT_RESET = 'context_reset',
  
  // Server → Client
  TRANSCRIPTION = 'transcription',
  ASSISTANT_MESSAGE = 'assistant_message',
  TTS_AUDIO = 'tts_audio',
  COMPLETION = 'completion',
  ERROR = 'error'
}

export interface BaseAgentEvent {
  type: AgentEventType;
  session_id: string;
  message_id: string;
  parent_id?: string; // Links messages in a conversation chain
  timestamp: number;
}

// Client → Server: Text command
export interface CommandTextEvent extends BaseAgentEvent {
  type: AgentEventType.COMMAND_TEXT;
  payload: {
    text: string;
  };
}

// Client → Server: Voice command (base64 audio)
export interface CommandVoiceEvent extends BaseAgentEvent {
  type: AgentEventType.COMMAND_VOICE;
  payload: {
    audio_base64: string;
    format: 'wav' | 'm4a' | 'opus';
  };
}

// Server → Client: Transcription result
export interface TranscriptionEvent extends BaseAgentEvent {
  type: AgentEventType.TRANSCRIPTION;
  payload: {
    text: string;
    confidence?: number;
  };
}

// Server → Client: Assistant response chunk
export interface AssistantMessageEvent extends BaseAgentEvent {
  type: AgentEventType.ASSISTANT_MESSAGE;
  payload: {
    content: string;
    is_final: boolean;
    metadata?: {
      tool_name?: string;
      tool_input?: string;
      tool_output?: string;
      thinking?: string;
    };
  };
}

// Server → Client: TTS audio ready
export interface TTSAudioEvent extends BaseAgentEvent {
  type: AgentEventType.TTS_AUDIO;
  payload: {
    audio_base64: string;
    format: 'mp3' | 'opus';
    duration_ms: number;
    transcript: string;
  };
}

// Server → Client: Command execution completed
export interface CompletionEvent extends BaseAgentEvent {
  type: AgentEventType.COMPLETION;
  payload: {
    success: boolean;
    result?: string;
    error?: string;
  };
}

// Server → Client: Error occurred
export interface ErrorEvent extends BaseAgentEvent {
  type: AgentEventType.ERROR;
  payload: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
  };
}

// Client → Server: Reset conversation context
export interface ContextResetEvent extends BaseAgentEvent {
  type: AgentEventType.CONTEXT_RESET;
  payload: Record<string, never>; // Empty payload
}

export type AgentEvent =
  | CommandTextEvent
  | CommandVoiceEvent
  | TranscriptionEvent
  | AssistantMessageEvent
  | TTSAudioEvent
  | CompletionEvent
  | ErrorEvent
  | ContextResetEvent;

// Type guards
export function isCommandTextEvent(event: AgentEvent): event is CommandTextEvent {
  return event.type === AgentEventType.COMMAND_TEXT;
}

export function isCommandVoiceEvent(event: AgentEvent): event is CommandVoiceEvent {
  return event.type === AgentEventType.COMMAND_VOICE;
}

export function isTranscriptionEvent(event: AgentEvent): event is TranscriptionEvent {
  return event.type === AgentEventType.TRANSCRIPTION;
}

export function isAssistantMessageEvent(event: AgentEvent): event is AssistantMessageEvent {
  return event.type === AgentEventType.ASSISTANT_MESSAGE;
}

export function isTTSAudioEvent(event: AgentEvent): event is TTSAudioEvent {
  return event.type === AgentEventType.TTS_AUDIO;
}

export function isCompletionEvent(event: AgentEvent): event is CompletionEvent {
  return event.type === AgentEventType.COMPLETION;
}

export function isErrorEvent(event: AgentEvent): event is ErrorEvent {
  return event.type === AgentEventType.ERROR;
}

export function isContextResetEvent(event: AgentEvent): event is ContextResetEvent {
  return event.type === AgentEventType.CONTEXT_RESET;
}

