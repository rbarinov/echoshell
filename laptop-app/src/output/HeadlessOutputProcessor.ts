import type { TerminalType } from '../terminal/TerminalManager';

export interface ParsedHeadlessOutput {
  assistantText: string | null;
  sessionId: string | null;
  isResult: boolean;
  isComplete: boolean;
}

/**
 * Processes raw output from headless terminals (cursor, claude)
 * Extracts JSON, parses assistant messages, detects completion
 */
export class HeadlessOutputProcessor {
  /**
   * Parse a single line of output from headless terminal
   */
  parseLine(line: string, terminalType: TerminalType): ParsedHeadlessOutput {
    const trimmed = line.trim();
    if (!trimmed) {
      return {
        assistantText: null,
        sessionId: null,
        isResult: false,
        isComplete: false
      };
    }

    try {
      const payload = JSON.parse(trimmed);
      if (!payload || typeof payload !== 'object') {
        return {
          assistantText: null,
          sessionId: null,
          isResult: false,
          isComplete: false
        };
      }

      // Extract session_id
      const sessionId = this.extractSessionId(payload);

      // Check if this is a result message (completion)
      const isResult = payload.type === 'result' && payload.subtype === 'success';
      if (isResult) {
        return {
          assistantText: null,
          sessionId,
          isResult: true,
          isComplete: true
        };
      }

      // Extract assistant message text
      const assistantText = this.extractAssistantText(payload);
      
      return {
        assistantText,
        sessionId,
        isResult: false,
        isComplete: false
      };
    } catch (error) {
      // Not JSON, return as-is (might be shell output)
      return {
        assistantText: null,
        sessionId: null,
        isResult: false,
        isComplete: false
      };
    }
  }

  /**
   * Process multiple lines of output
   */
  processChunk(data: string, terminalType: TerminalType): {
    assistantMessages: string[];
    sessionId: string | null;
    isComplete: boolean;
    rawOutput: string; // For terminal display
  } {
    const lines = data.split('\n');
    const assistantMessages: string[] = [];
    let sessionId: string | null = null;
    let isComplete = false;
    const rawOutput: string[] = [];

    for (const line of lines) {
      const parsed = this.parseLine(line, terminalType);
      
      if (parsed.sessionId) {
        sessionId = parsed.sessionId;
      }

      if (parsed.isComplete) {
        isComplete = true;
        // Don't include result messages in output
        continue;
      }

      if (parsed.assistantText) {
        assistantMessages.push(parsed.assistantText);
        // Include assistant text in raw output (for terminal display)
        rawOutput.push(parsed.assistantText);
      } else {
        // Non-JSON or non-assistant output - include as-is
        rawOutput.push(line);
      }
    }

    return {
      assistantMessages,
      sessionId,
      isComplete,
      rawOutput: rawOutput.join('\n')
    };
  }

  private extractSessionId(payload: any): string | null {
    const candidates = [
      payload.session_id,
      payload.sessionId,
      payload.message?.session_id,
      payload.message?.sessionId,
      payload.result?.session_id,
      payload.result?.sessionId
    ];

    for (const candidate of candidates) {
      if (typeof candidate === 'string' && candidate.trim().length > 0) {
        return candidate.trim();
      }
    }

    return null;
  }

  private extractAssistantText(payload: any): string | null {
    if (payload.type !== 'assistant' || !payload.message?.content) {
      return null;
    }

    interface ContentBlock {
      type?: string;
      text?: string;
    }

    const parts = Array.isArray(payload.message.content)
      ? payload.message.content
          .map((block: ContentBlock) => {
            if (block.type === 'text' && block.text) {
              return block.text;
            }
            return null;
          })
          .filter((text: string | null): text is string => text !== null)
      : [];

    return parts.length > 0 ? parts.join('\n') : null;
  }
}
