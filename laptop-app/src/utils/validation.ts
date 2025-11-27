import { z } from 'zod';
import type { TunnelResponse } from '../types';

/**
 * Validate request body against Zod schema
 * Returns validated data or error response
 */
export function validateRequest<T>(
  schema: z.ZodSchema<T>,
  data: unknown
): { success: true; data: T } | { success: false; response: TunnelResponse } {
  try {
    const validated = schema.parse(data);
    return { success: true, data: validated };
  } catch (error) {
    if (error instanceof z.ZodError) {
      const errors = error.errors.map((err) => ({
        path: err.path.join('.'),
        message: err.message
      }));

      return {
        success: false,
        response: {
          statusCode: 400,
          body: {
            error: 'Validation failed',
            details: errors
          }
        }
      };
    }

    return {
      success: false,
      response: {
        statusCode: 500,
        body: {
          error: 'Validation error',
          message: error instanceof Error ? error.message : 'Unknown error'
        }
      }
    };
  }
}

/**
 * Validate query parameters against Zod schema
 */
export function validateQuery<T>(
  schema: z.ZodSchema<T>,
  query: Record<string, string | undefined>
): { success: true; data: T } | { success: false; response: TunnelResponse } {
  try {
    const validated = schema.parse(query);
    return { success: true, data: validated };
  } catch (error) {
    if (error instanceof z.ZodError) {
      const errors = error.errors.map((err) => ({
        path: err.path.join('.'),
        message: err.message
      }));

      return {
        success: false,
        response: {
          statusCode: 400,
          body: {
            error: 'Query validation failed',
            details: errors
          }
        }
      };
    }

    return {
      success: false,
      response: {
        statusCode: 500,
        body: {
          error: 'Query validation error',
          message: error instanceof Error ? error.message : 'Unknown error'
        }
      }
    };
  }
}
