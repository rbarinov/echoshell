import { z } from 'zod';

export const RequestKeysRequestSchema = z.object({
  device_id: z.string().min(1, 'device_id is required'),
  tunnel_id: z.string().optional(),
  duration_seconds: z.number().int().positive().optional(),
  permissions: z.array(z.string()).optional()
});

export const RefreshKeysRequestSchema = z.object({
  device_id: z.string().min(1, 'device_id is required')
});

export const RevokeKeysQuerySchema = z.object({
  device_id: z.string().min(1, 'device_id is required')
});

export type RequestKeysRequest = z.infer<typeof RequestKeysRequestSchema>;
export type RefreshKeysRequest = z.infer<typeof RefreshKeysRequestSchema>;
export type RevokeKeysQuery = z.infer<typeof RevokeKeysQuerySchema>;
