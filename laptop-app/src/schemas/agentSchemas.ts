import { z } from 'zod';

export const ExecuteAgentRequestSchema = z.object({
  command: z.string().min(1, 'command is required'),
  session_id: z.string().optional()
});

export type ExecuteAgentRequest = z.infer<typeof ExecuteAgentRequestSchema>;
