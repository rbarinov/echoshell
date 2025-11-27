import { describe, it, expect } from '@jest/globals';
import {
  CreateTerminalRequestSchema,
  ExecuteCommandRequestSchema,
  RenameSessionRequestSchema,
  ResizeTerminalRequestSchema,
  TerminalTypeSchema
} from '../terminalSchemas';

describe('TerminalSchemas', () => {
  describe('TerminalTypeSchema', () => {
    it('should accept valid terminal types', () => {
      expect(TerminalTypeSchema.parse('regular')).toBe('regular');
      // cursor_agent removed, using cursor instead
      expect(TerminalTypeSchema.parse('cursor')).toBe('cursor');
      expect(TerminalTypeSchema.parse('claude')).toBe('claude');
    });

    it('should reject invalid terminal types', () => {
      expect(() => TerminalTypeSchema.parse('invalid')).toThrow();
      expect(() => TerminalTypeSchema.parse('')).toThrow();
    });
  });

  describe('CreateTerminalRequestSchema', () => {
    it('should accept valid request', () => {
      const result = CreateTerminalRequestSchema.parse({
        terminal_type: 'regular',
        working_dir: '/tmp',
        name: 'test-session'
      });

      expect(result.terminal_type).toBe('regular');
      expect(result.working_dir).toBe('/tmp');
      expect(result.name).toBe('test-session');
    });

    it('should accept minimal request', () => {
      const result = CreateTerminalRequestSchema.parse({
        terminal_type: 'cursor'
      });

      expect(result.terminal_type).toBe('cursor');
      expect(result.working_dir).toBeUndefined();
      expect(result.name).toBeUndefined();
    });

    it('should reject missing terminal_type', () => {
      expect(() => CreateTerminalRequestSchema.parse({})).toThrow();
    });
  });

  describe('ExecuteCommandRequestSchema', () => {
    it('should accept valid command', () => {
      const result = ExecuteCommandRequestSchema.parse({
        command: 'ls -la'
      });

      expect(result.command).toBe('ls -la');
    });

    it('should reject missing command', () => {
      expect(() => ExecuteCommandRequestSchema.parse({})).toThrow();
    });
  });

  describe('RenameSessionRequestSchema', () => {
    it('should accept valid name', () => {
      const result = RenameSessionRequestSchema.parse({
        name: 'new-name'
      });

      expect(result.name).toBe('new-name');
    });

    it('should reject empty name', () => {
      expect(() => RenameSessionRequestSchema.parse({ name: '' })).toThrow();
    });

    it('should reject missing name', () => {
      expect(() => RenameSessionRequestSchema.parse({})).toThrow();
    });
  });

  describe('ResizeTerminalRequestSchema', () => {
    it('should accept valid dimensions', () => {
      const result = ResizeTerminalRequestSchema.parse({
        cols: 80,
        rows: 24
      });

      expect(result.cols).toBe(80);
      expect(result.rows).toBe(24);
    });

    it('should reject negative dimensions', () => {
      expect(() => ResizeTerminalRequestSchema.parse({ cols: -1, rows: 24 })).toThrow();
      expect(() => ResizeTerminalRequestSchema.parse({ cols: 80, rows: -1 })).toThrow();
    });

    it('should reject zero dimensions', () => {
      expect(() => ResizeTerminalRequestSchema.parse({ cols: 0, rows: 24 })).toThrow();
      expect(() => ResizeTerminalRequestSchema.parse({ cols: 80, rows: 0 })).toThrow();
    });

    it('should reject non-integer dimensions', () => {
      expect(() => ResizeTerminalRequestSchema.parse({ cols: 80.5, rows: 24 })).toThrow();
    });
  });
});
