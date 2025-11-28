import { randomUUID } from 'crypto';
import type { ChatMessage, ChatMessageType } from '../terminal/types';

/**
 * Parses JSON stream output from headless terminals and converts to ChatMessage objects
 */
export class AgentOutputParser {
  /**
   * Parse a single JSON line and convert to ChatMessage
   * @param jsonLine - Single line of JSON output
   * @returns Parsed message, session ID, and completion status
   */
  parseLine(jsonLine: string): {
    message: ChatMessage | null;
    sessionId: string | null;
    isComplete: boolean; // true if result message
  } {
    const trimmed = jsonLine.trim();
    if (!trimmed) {
      return {
        message: null,
        sessionId: null,
        isComplete: false,
      };
    }

    try {
      const payload = JSON.parse(trimmed);
      if (!payload || typeof payload !== 'object') {
        return {
          message: null,
          sessionId: null,
          isComplete: false,
        };
      }

      // Extract session_id
      const sessionId = this.extractSessionId(payload);

      // Check if this is a result message (completion indicator, not a chat message)
      const isResult = payload.type === 'result' || payload.type === 'session_end';
      if (isResult) {
        return {
          message: null,
          sessionId,
          isComplete: true,
        };
      }

      // Map to ChatMessage
      const message = this.mapToChatMessage(payload);
      
      return {
        message,
        sessionId,
        isComplete: false,
      };
    } catch (error) {
      // Not valid JSON, skip gracefully
      console.debug(`⚠️ [AgentOutputParser] Failed to parse JSON line: ${trimmed.substring(0, 100)}`);
      return {
        message: null,
        sessionId: null,
        isComplete: false,
      };
    }
  }

  /**
   * Map JSON payload to ChatMessage
   */
  private mapToChatMessage(payload: any): ChatMessage | null {
    const messageType = this.determineMessageType(payload);
    if (!messageType) {
      return null; // Unknown or unsupported message type
    }

    const content = this.extractContent(payload, messageType);
    if (!content) {
      return null; // No content to display
    }

    const metadata = this.extractMetadata(payload, messageType);

    return {
      id: randomUUID(),
      timestamp: payload.timestamp || Date.now(),
      type: messageType,
      content,
      metadata,
    };
  }

  /**
   * Determine ChatMessage type from JSON payload
   */
  private determineMessageType(payload: any): ChatMessageType | null {
    // Handle cursor-agent format
    if (payload.type === 'user') {
      return 'user';
    }
    if (payload.type === 'assistant') {
      return 'assistant';
    }
    if (payload.type === 'tool' || payload.tool_name) {
      return 'tool';
    }
    if (payload.type?.startsWith('system/') || payload.type === 'system') {
      return 'system';
    }
    if (payload.type === 'error' || payload.error) {
      return 'error';
    }

    // Handle claude CLI format
    if (payload.role === 'user') {
      return 'user';
    }
    if (payload.role === 'assistant') {
      return 'assistant';
    }
    if (payload.type === 'tool_use' || payload.type === 'tool_result') {
      return 'tool';
    }
    if (payload.type === 'message' && payload.role) {
      return payload.role === 'user' ? 'user' : 'assistant';
    }

    return null;
  }

  /**
   * Extract content text from payload based on message type
   */
  private extractContent(payload: any, messageType: ChatMessageType): string | null {
    switch (messageType) {
      case 'user':
        // Cursor format: payload.content (string)
        // Claude format: payload.content (string or array)
        if (typeof payload.content === 'string') {
          return payload.content;
        }
        if (Array.isArray(payload.content)) {
          return payload.content
            .map((block: any) => (block.type === 'text' ? block.text : null))
            .filter((text: string | null): text is string => text !== null)
            .join('\n');
        }
        return null;

      case 'assistant':
        // Cursor format: payload.message.content (array of blocks)
        // Claude format: payload.content (string or array)
        if (payload.message?.content) {
          // Cursor format
          const content = payload.message.content;
          if (Array.isArray(content)) {
            return content
              .map((block: any) => {
                if (block.type === 'text' && block.text) {
                  return block.text;
                }
                return null;
              })
              .filter((text: string | null): text is string => text !== null)
              .join('\n');
          }
        }
        if (payload.content) {
          // Claude format
          if (typeof payload.content === 'string') {
            return payload.content;
          }
          if (Array.isArray(payload.content)) {
            return payload.content
              .map((block: any) => (block.type === 'text' ? block.text : null))
              .filter((text: string | null): text is string => text !== null)
              .join('\n');
          }
        }
        return null;

      case 'tool':
        // Tool name and input/output
        const toolName = payload.tool_name || payload.name || 'unknown';
        const toolInput = payload.input || payload.tool_input || '';
        const toolOutput = payload.output || payload.tool_output || '';
        
        let toolContent = `Tool: ${toolName}`;
        if (toolInput) {
          toolContent += `\nInput: ${toolInput}`;
        }
        if (toolOutput) {
          toolContent += `\nOutput: ${toolOutput}`;
        }
        return toolContent;

      case 'system':
        // System messages
        return payload.message || payload.content || payload.text || 'System message';

      case 'error':
        // Error messages
        return payload.message || payload.error || payload.content || 'Error occurred';

      default:
        return null;
    }
  }

  /**
   * Extract metadata from payload based on message type
   */
  private extractMetadata(payload: any, messageType: ChatMessageType): ChatMessage['metadata'] | undefined {
    if (messageType === 'tool') {
      return {
        toolName: payload.tool_name || payload.name,
        toolInput: payload.input || payload.tool_input,
        toolOutput: payload.output || payload.tool_output,
      };
    }

    if (messageType === 'assistant' && payload.thinking) {
      return {
        thinking: payload.thinking,
      };
    }

    if (messageType === 'error') {
      return {
        errorCode: payload.error_code || payload.code,
        stackTrace: payload.stack_trace || payload.stackTrace,
      };
    }

    return undefined;
  }

  /**
   * Extract session_id from payload (supports various formats)
   */
  private extractSessionId(payload: any): string | null {
    const candidates = [
      payload.session_id,
      payload.sessionId,
      payload.message?.session_id,
      payload.message?.sessionId,
      payload.result?.session_id,
      payload.result?.sessionId,
    ];

    for (const candidate of candidates) {
      if (typeof candidate === 'string' && candidate.trim().length > 0) {
        return candidate.trim();
      }
    }

    return null;
  }
}
