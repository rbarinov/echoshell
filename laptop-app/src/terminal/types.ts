/**
 * Types for terminal and chat functionality
 */

export type HeadlessTerminalType = 'cursor' | 'claude';
export type TerminalType = 'regular' | HeadlessTerminalType;

/**
 * Chat message types for headless terminals
 */
export type ChatMessageType = 'user' | 'assistant' | 'tool' | 'system' | 'error';

/**
 * Metadata for chat messages
 */
export interface ChatMessageMetadata {
  toolName?: string;
  toolInput?: string;
  toolOutput?: string;
  thinking?: string;
  errorCode?: string;
  stackTrace?: string;
}

/**
 * Structured chat message for headless terminal output
 */
export interface ChatMessage {
  id: string; // UUID for message
  timestamp: number; // Unix timestamp
  type: ChatMessageType;
  content: string; // Main message text
  metadata?: ChatMessageMetadata;
}

/**
 * Chat history for a terminal session
 */
export interface ChatHistory {
  sessionId: string;
  messages: ChatMessage[];
  createdAt: number;
  updatedAt: number;
}

/**
 * Current execution state for headless terminals
 */
export interface CurrentExecution {
  isRunning: boolean;
  cliSessionId?: string; // Session ID from CLI for context preservation
  startedAt: number;
  currentMessages: ChatMessage[]; // Messages from current execution
}
