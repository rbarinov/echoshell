import { describe, it, expect, beforeEach } from '@jest/globals';
import { HeadlessOutputProcessor } from '../HeadlessOutputProcessor';

/**
 * Tests for HeadlessOutputProcessor (Legacy)
 * 
 * NOTE: This processor is still used in RecordingStreamManager for backward compatibility.
 * New headless terminals use AgentOutputParser instead, which converts JSON to ChatMessage objects.
 * 
 * See: AgentOutputParser for the new parsing approach.
 */
describe('HeadlessOutputProcessor', () => {
  let processor: HeadlessOutputProcessor;

  beforeEach(() => {
    processor = new HeadlessOutputProcessor();
  });

  describe('parseLine', () => {
    it('should parse assistant message from cursor', () => {
      const line = JSON.stringify({
        type: 'assistant',
        message: {
          content: [{ type: 'text', text: 'Hello world' }]
        },
        session_id: 'test-session-123'
      });

      const result = processor.parseLine(line, 'cursor');

      expect(result.assistantText).toBe('Hello world');
      expect(result.sessionId).toBe('test-session-123');
      expect(result.isResult).toBe(false);
      expect(result.isComplete).toBe(false);
    });

    it('should parse result message', () => {
      const line = JSON.stringify({
        type: 'result',
        subtype: 'success',
        session_id: 'test-session-123'
      });

      const result = processor.parseLine(line, 'cursor');

      expect(result.assistantText).toBeNull();
      expect(result.sessionId).toBe('test-session-123');
      expect(result.isResult).toBe(true);
      expect(result.isComplete).toBe(true);
    });

    it('should handle non-JSON lines', () => {
      const result = processor.parseLine('regular shell output', 'cursor');

      expect(result.assistantText).toBeNull();
      expect(result.sessionId).toBeNull();
      expect(result.isResult).toBe(false);
      expect(result.isComplete).toBe(false);
    });

    it('should handle empty lines', () => {
      const result = processor.parseLine('', 'cursor');

      expect(result.assistantText).toBeNull();
      expect(result.sessionId).toBeNull();
      expect(result.isResult).toBe(false);
      expect(result.isComplete).toBe(false);
    });

    it('should extract session_id from various locations', () => {
      const testCases = [
        { session_id: 'test-1' },
        { sessionId: 'test-2' },
        { message: { session_id: 'test-3' } },
        { result: { sessionId: 'test-4' } }
      ];

      testCases.forEach((payload, index) => {
        const line = JSON.stringify(payload);
        const result = processor.parseLine(line, 'cursor');
        expect(result.sessionId).toBe(`test-${index + 1}`);
      });
    });
  });

  describe('processChunk', () => {
    it('should process multiple lines and extract assistant messages', () => {
      const data = [
        JSON.stringify({
          type: 'assistant',
          message: { content: [{ type: 'text', text: 'First message' }] }
        }),
        JSON.stringify({
          type: 'assistant',
          message: { content: [{ type: 'text', text: 'Second message' }] }
        }),
        'regular output'
      ].join('\n');

      const result = processor.processChunk(data, 'cursor');

      expect(result.assistantMessages).toHaveLength(2);
      expect(result.assistantMessages[0]).toBe('First message');
      expect(result.assistantMessages[1]).toBe('Second message');
      expect(result.isComplete).toBe(false);
    });

    it('should detect completion from result message', () => {
      const data = [
        JSON.stringify({
          type: 'assistant',
          message: { content: [{ type: 'text', text: 'Message' }] }
        }),
        JSON.stringify({
          type: 'result',
          subtype: 'success'
        })
      ].join('\n');

      const result = processor.processChunk(data, 'cursor');

      expect(result.isComplete).toBe(true);
      expect(result.assistantMessages).toHaveLength(1);
    });

    it('should extract session_id from chunk', () => {
      const data = JSON.stringify({
        type: 'assistant',
        message: { content: [{ type: 'text', text: 'Test' }] },
        session_id: 'chunk-session-123'
      });

      const result = processor.processChunk(data, 'cursor');

      expect(result.sessionId).toBe('chunk-session-123');
    });

    it('should include raw output for terminal display', () => {
      const data = [
        JSON.stringify({
          type: 'assistant',
          message: { content: [{ type: 'text', text: 'Message' }] }
        }),
        'regular output'
      ].join('\n');

      const result = processor.processChunk(data, 'cursor');

      expect(result.rawOutput).toContain('Message');
      expect(result.rawOutput).toContain('regular output');
    });
  });
});
