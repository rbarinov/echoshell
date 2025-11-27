import { z } from 'zod';

export const CreateWorkspaceRequestSchema = z.object({
  workspace_name: z.string().min(1, 'workspace_name is required')
});

export const CloneRepositoryRequestSchema = z.object({
  repo_url: z.string().url('repo_url must be a valid URL'),
  repo_name: z.string().optional()
});

export const CreateWorktreeRequestSchema = z.object({
  branch_or_feature: z.string().min(1, 'branch_or_feature is required'),
  worktree_name: z.string().optional()
});

export type CreateWorkspaceRequest = z.infer<typeof CreateWorkspaceRequestSchema>;
export type CloneRepositoryRequest = z.infer<typeof CloneRepositoryRequestSchema>;
export type CreateWorktreeRequest = z.infer<typeof CreateWorktreeRequestSchema>;
