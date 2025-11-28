import { z } from 'zod';

const ALLOWED_TERMINAL_TYPES = ['regular', 'cursor', 'claude', 'agent'] as const;

export const TerminalTypeSchema = z.enum(ALLOWED_TERMINAL_TYPES);

export const CreateTerminalRequestSchema = z.object({
  terminal_type: TerminalTypeSchema,
  working_dir: z.string().optional(),
  name: z.string().optional()
});

export const ExecuteCommandRequestSchema = z.object({
  command: z.string()
});

export const RenameSessionRequestSchema = z.object({
  name: z.string().min(1, 'Name must not be empty')
});

export const ResizeTerminalRequestSchema = z.object({
  cols: z.number().int().positive(),
  rows: z.number().int().positive()
});

export type CreateTerminalRequest = z.infer<typeof CreateTerminalRequestSchema>;
export type ExecuteCommandRequest = z.infer<typeof ExecuteCommandRequestSchema>;
export type RenameSessionRequest = z.infer<typeof RenameSessionRequestSchema>;
export type ResizeTerminalRequest = z.infer<typeof ResizeTerminalRequestSchema>;
