import { Router } from 'express';
import type { WorkspaceManager } from '../workspace/WorkspaceManager';
import type { WorktreeManager } from '../workspace/WorktreeManager';
import {
  CreateWorkspaceRequestSchema,
  CloneRepositoryRequestSchema,
  CreateWorktreeRequestSchema
} from '../schemas/workspaceSchemas';

export function createWorkspaceRoutes(
  workspaceManager: WorkspaceManager,
  worktreeManager: WorktreeManager
): Router {
  const router = Router();

  router.get('/list', async (_req, res) => {
    try {
      const workspaces = await workspaceManager.listWorkspaces();
      res.json({
        workspaces: workspaces.map(w => ({
          name: w.name,
          path: w.path,
          created_at: w.createdAt
        }))
      });
    } catch (error) {
      res.status(500).json({ error: 'Failed to list workspaces' });
    }
  });

  router.post('/create', async (req, res) => {
    try {
      const validation = CreateWorkspaceRequestSchema.safeParse(req.body);
      if (!validation.success) {
        return res.status(400).json({
          error: 'Validation failed',
          details: validation.error.errors
        });
      }
      const { workspace_name } = validation.data;
      const workspace = await workspaceManager.createWorkspace(workspace_name);
      res.json({
        name: workspace.name,
        path: workspace.path,
        created_at: workspace.createdAt,
        status: 'created'
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  router.delete('/:workspace', async (req, res) => {
    try {
      const { workspace } = req.params;
      await workspaceManager.removeWorkspace(workspace);
      res.json({
        workspace,
        status: 'deleted'
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  router.post('/:workspace/clone', async (req, res) => {
    try {
      const { workspace } = req.params;
      const validation = CloneRepositoryRequestSchema.safeParse(req.body);
      if (!validation.success) {
        return res.status(400).json({
          error: 'Validation failed',
          details: validation.error.errors
        });
      }
      const { repo_url, repo_name } = validation.data;
      const repo = await workspaceManager.cloneRepository(workspace, repo_url, repo_name);
      res.json({
        name: repo.name,
        path: repo.path,
        remote_url: repo.remoteUrl,
        cloned_at: repo.clonedAt,
        status: 'cloned'
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  router.get('/:workspace/repos', async (req, res) => {
    try {
      const { workspace } = req.params;
      const repos = await workspaceManager.listRepositories(workspace);
      res.json({
        workspace,
        repositories: repos.map(r => ({
          name: r.name,
          path: r.path,
          remote_url: r.remoteUrl,
          cloned_at: r.clonedAt
        }))
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  router.post('/:workspace/:repo/worktree/create', async (req, res) => {
    try {
      const { workspace, repo } = req.params;
      const validation = CreateWorktreeRequestSchema.safeParse(req.body);
      if (!validation.success) {
        return res.status(400).json({
          error: 'Validation failed',
          details: validation.error.errors
        });
      }
      const { branch_or_feature, worktree_name } = validation.data;
      const worktree = await worktreeManager.createWorktree(workspace, repo, branch_or_feature, worktree_name);
      res.json({
        name: worktree.name,
        path: worktree.path,
        branch: worktree.branch,
        created_at: worktree.createdAt,
        status: 'created'
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  router.get('/:workspace/:repo/worktrees', async (req, res) => {
    try {
      const { workspace, repo } = req.params;
      const worktrees = await worktreeManager.listWorktrees(workspace, repo);
      res.json({
        workspace,
        repo,
        worktrees: worktrees.map(w => ({
          name: w.name,
          path: w.path,
          branch: w.branch,
          created_at: w.createdAt
        }))
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  router.delete('/:workspace/:repo/worktree/:name', async (req, res) => {
    try {
      const { workspace, repo, name } = req.params;
      await worktreeManager.removeWorktree(workspace, repo, name);
      res.json({
        workspace,
        repo,
        worktree: name,
        status: 'deleted'
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  router.get('/:workspace/:repo/worktree/:name/path', (req, res) => {
    try {
      const { workspace, repo, name } = req.params;
      const worktreePath = worktreeManager.getWorktreePath(workspace, repo, name);
      res.json({
        workspace,
        repo,
        worktree: name,
        path: worktreePath
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      res.status(500).json({ error: errorMessage });
    }
  });

  return router;
}
