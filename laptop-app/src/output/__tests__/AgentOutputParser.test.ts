import { describe, it, expect, beforeEach } from '@jest/globals';
import { AgentOutputParser } from '../AgentOutputParser';

describe('AgentOutputParser', () => {
  let parser: AgentOutputParser;

  beforeEach(() => {
    parser = new AgentOutputParser();
  });

  describe('parseLine', () => {
    it('should parse user message from cursor-agent format', () => {
      const jsonLine = JSON.stringify({
        type: 'user',
        content: 'List files',
        timestamp: 1234567890,
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).not.toBeNull();
      expect(result.message?.type).toBe('user');
      expect(result.message?.content).toBe('List files');
      expect(result.isComplete).toBe(false);
    });

    it('should parse assistant message from cursor-agent format', () => {
      const jsonLine = JSON.stringify({
        type: 'assistant',
        message: {
          content: [
            { type: 'text', text: 'I will list the files for you.' },
          ],
        },
        timestamp: 1234567891,
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).not.toBeNull();
      expect(result.message?.type).toBe('assistant');
      expect(result.message?.content).toBe('I will list the files for you.');
      expect(result.isComplete).toBe(false);
    });

    it('should parse tool message from cursor-agent format', () => {
      const jsonLine = JSON.stringify({
        type: 'tool',
        tool_name: 'bash',
        input: 'ls -la',
        output: 'file1.txt\nfile2.py',
        timestamp: 1234567892,
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).not.toBeNull();
      expect(result.message?.type).toBe('tool');
      expect(result.message?.metadata?.toolName).toBe('bash');
      expect(result.message?.metadata?.toolInput).toBe('ls -la');
      expect(result.message?.metadata?.toolOutput).toBe('file1.txt\nfile2.py');
      expect(result.isComplete).toBe(false);
    });

    it('should parse result message and mark as complete', () => {
      const jsonLine = JSON.stringify({
        type: 'result',
        success: true,
        session_id: 'abc123',
        timestamp: 1234567893,
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).toBeNull();
      expect(result.sessionId).toBe('abc123');
      expect(result.isComplete).toBe(true);
    });

    it('should extract session_id from various locations', () => {
      const jsonLine = JSON.stringify({
        type: 'system/init',
        session_id: 'xyz789',
        timestamp: 1234567890,
      });

      const result = parser.parseLine(jsonLine);

      expect(result.sessionId).toBe('xyz789');
    });

    it('should handle malformed JSON gracefully', () => {
      const result = parser.parseLine('not valid json');

      expect(result.message).toBeNull();
      expect(result.sessionId).toBeNull();
      expect(result.isComplete).toBe(false);
    });

    it('should handle empty lines', () => {
      const result = parser.parseLine('');

      expect(result.message).toBeNull();
      expect(result.sessionId).toBeNull();
      expect(result.isComplete).toBe(false);
    });

    it('should parse claude CLI format messages', () => {
      const jsonLine = JSON.stringify({
        type: 'message',
        role: 'assistant',
        content: 'I will help you list files.',
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).not.toBeNull();
      expect(result.message?.type).toBe('assistant');
      expect(result.message?.content).toBe('I will help you list files.');
    });

    it('should parse claude tool_use format', () => {
      const jsonLine = JSON.stringify({
        type: 'tool_use',
        name: 'bash',
        input: 'ls -la',
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).not.toBeNull();
      expect(result.message?.type).toBe('tool');
      expect(result.message?.metadata?.toolName).toBe('bash');
      expect(result.message?.metadata?.toolInput).toBe('ls -la');
    });

    it('should handle system messages', () => {
      const jsonLine = JSON.stringify({
        type: 'system/init',
        message: 'System initialized',
        session_id: 'sys123',
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).not.toBeNull();
      expect(result.message?.type).toBe('system');
      expect(result.message?.content).toBe('System initialized');
      expect(result.sessionId).toBe('sys123');
    });

    it('should handle error messages', () => {
      const jsonLine = JSON.stringify({
        type: 'error',
        message: 'Command failed',
        error_code: 'EACCES',
      });

      const result = parser.parseLine(jsonLine);

      expect(result.message).not.toBeNull();
      expect(result.message?.type).toBe('error');
      expect(result.message?.content).toBe('Command failed');
      expect(result.message?.metadata?.errorCode).toBe('EACCES');
    });

    it('should generate unique IDs for messages', () => {
      const jsonLine1 = JSON.stringify({
        type: 'assistant',
        message: { content: [{ type: 'text', text: 'Message 1' }] },
      });
      const jsonLine2 = JSON.stringify({
        type: 'assistant',
        message: { content: [{ type: 'text', text: 'Message 2' }] },
      });

      const result1 = parser.parseLine(jsonLine1);
      const result2 = parser.parseLine(jsonLine2);

      expect(result1.message?.id).not.toBe(result2.message?.id);
    });
  });
});
