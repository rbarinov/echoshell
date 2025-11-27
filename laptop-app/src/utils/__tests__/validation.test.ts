import { describe, it, expect } from '@jest/globals';
import { z } from 'zod';
import { validateRequest, validateQuery } from '../validation';
import type { TunnelResponse } from '../../types';

describe('validation', () => {
  const TestSchema = z.object({
    name: z.string().min(1),
    age: z.number().int().positive().optional()
  });

  describe('validateRequest', () => {
    it('should return success for valid data', () => {
      const result = validateRequest(TestSchema, { name: 'John', age: 30 });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.name).toBe('John');
        expect(result.data.age).toBe(30);
      }
    });

    it('should return error response for invalid data', () => {
      const result = validateRequest(TestSchema, { name: '' });

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.response.statusCode).toBe(400);
        expect(result.response.body).toHaveProperty('error');
        expect(result.response.body).toHaveProperty('details');
      }
    });

    it('should return error response for missing required fields', () => {
      const result = validateRequest(TestSchema, {});

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.response.statusCode).toBe(400);
      }
    });
  });

  describe('validateQuery', () => {
    const QuerySchema = z.object({
      id: z.string().min(1),
      page: z.string().optional()
    });

    it('should return success for valid query', () => {
      const result = validateQuery(QuerySchema, { id: '123', page: '1' });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.id).toBe('123');
        expect(result.data.page).toBe('1');
      }
    });

    it('should return error response for invalid query', () => {
      const result = validateQuery(QuerySchema, { id: '' });

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.response.statusCode).toBe(400);
        expect(result.response.body).toHaveProperty('error');
      }
    });

    it('should handle undefined values in query', () => {
      const result = validateQuery(QuerySchema, { id: '123', page: undefined });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.id).toBe('123');
        expect(result.data.page).toBeUndefined();
      }
    });
  });
});
