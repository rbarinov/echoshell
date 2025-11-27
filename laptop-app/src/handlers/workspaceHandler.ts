import type { WorkspaceManager } from '../workspace/WorkspaceManager';
import type { WorktreeManager } from '../workspace/WorktreeManager';
import type { TunnelRequest, TunnelResponse } from '../types';
import {
  CreateWorkspaceRequestSchema,
  CloneRepositoryRequestSchema,
  CreateWorktreeRequestSchema
} from '../schemas/workspaceSchemas';
import { validateRequest } from '../utils/validation';

export class WorkspaceHandler {
  constructor(
    private workspaceManager: WorkspaceManager,
    private worktreeManager: WorktreeManager
  ) {}

  async handleRequest(req: TunnelRequest): Promise<TunnelResponse> {
    const { method, path, body, query } = req;

    // Workspace management
    if (path === '/workspace/list' && method === 'GET') {
      return this.handleList();
    }

    if (path === '/workspace/create' && method === 'POST') {
      return this.handleCreate(body);
    }

    const workspaceMatch = path.match(/^\/workspace\/([^\/]+)$/);
    if (workspaceMatch && method === 'DELETE') {
      return this.handleDelete(workspaceMatch[1]);
    }

    // Repository management
    const cloneMatch = path.match(/^\/workspace\/([^\/]+)\/clone$/);
    if (cloneMatch && method === 'POST') {
      return this.handleClone(cloneMatch[1], body);
    }

    const reposMatch = path.match(/^\/workspace\/([^\/]+)\/repos$/);
    if (reposMatch && method === 'GET') {
      return this.handleListRepos(reposMatch[1]);
    }

    // Worktree management
    const worktreeCreateMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktree\/create$/);
    if (worktreeCreateMatch && method === 'POST') {
      return this.handleCreateWorktree(worktreeCreateMatch[1], worktreeCreateMatch[2], body);
    }

    const worktreesMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktrees$/);
    if (worktreesMatch && method === 'GET') {
      return this.handleListWorktrees(worktreesMatch[1], worktreesMatch[2]);
    }

    const worktreeDeleteMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktree\/([^\/]+)$/);
    if (worktreeDeleteMatch && method === 'DELETE') {
      return this.handleDeleteWorktree(worktreeDeleteMatch[1], worktreeDeleteMatch[2], worktreeDeleteMatch[3]);
    }

    const worktreePathMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktree\/([^\/]+)\/path$/);
    if (worktreePathMatch && method === 'GET') {
      return this.handleGetWorktreePath(worktreePathMatch[1], worktreePathMatch[2], worktreePathMatch[3]);
    }

    return { statusCode: 404, body: { error: 'Not found' } };
  }

  private async handleList(): Promise<TunnelResponse> {
    try {
      const workspaces = await this.workspaceManager.listWorkspaces();
      return {
        statusCode: 200,
        body: {
          workspaces: workspaces.map(w => ({
            name: w.name,
            path: w.path,
            created_at: w.createdAt
          }))
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleCreate(body: unknown): Promise<TunnelResponse> {
    try {
      const validation = validateRequest(CreateWorkspaceRequestSchema, body);
      if (!validation.success) {
        return validation.response;
      }

      const { workspace_name } = validation.data;
      const workspace = await this.workspaceManager.createWorkspace(workspace_name);
      return {
        statusCode: 200,
        body: {
          name: workspace.name,
          path: workspace.path,
          created_at: workspace.createdAt,
          status: 'created'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleDelete(workspace: string): Promise<TunnelResponse> {
    try {
      await this.workspaceManager.removeWorkspace(workspace);
      return {
        statusCode: 200,
        body: {
          workspace,
          status: 'deleted'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleClone(workspace: string, body: unknown): Promise<TunnelResponse> {
    try {
      const validation = validateRequest(CloneRepositoryRequestSchema, body);
      if (!validation.success) {
        return validation.response;
      }

      const { repo_url, repo_name } = validation.data;
      const repo = await this.workspaceManager.cloneRepository(workspace, repo_url, repo_name);
      return {
        statusCode: 200,
        body: {
          name: repo.name,
          path: repo.path,
          remote_url: repo.remoteUrl,
          cloned_at: repo.clonedAt,
          status: 'cloned'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleListRepos(workspace: string): Promise<TunnelResponse> {
    try {
      const repos = await this.workspaceManager.listRepositories(workspace);
      return {
        statusCode: 200,
        body: {
          workspace,
          repositories: repos.map(r => ({
            name: r.name,
            path: r.path,
            remote_url: r.remoteUrl,
            cloned_at: r.clonedAt
          }))
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleCreateWorktree(workspace: string, repo: string, body: unknown): Promise<TunnelResponse> {
    try {
      const validation = validateRequest(CreateWorktreeRequestSchema, body);
      if (!validation.success) {
        return validation.response;
      }

      const { branch_or_feature, worktree_name } = validation.data;
      const worktree = await this.worktreeManager.createWorktree(workspace, repo, branch_or_feature, worktree_name);
      return {
        statusCode: 200,
        body: {
          name: worktree.name,
          path: worktree.path,
          branch: worktree.branch,
          created_at: worktree.createdAt,
          status: 'created'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleListWorktrees(workspace: string, repo: string): Promise<TunnelResponse> {
    try {
      const worktrees = await this.worktreeManager.listWorktrees(workspace, repo);
      return {
        statusCode: 200,
        body: {
          workspace,
          repo,
          worktrees: worktrees.map(w => ({
            name: w.name,
            path: w.path,
            branch: w.branch,
            created_at: w.createdAt
          }))
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleDeleteWorktree(workspace: string, repo: string, worktreeName: string): Promise<TunnelResponse> {
    try {
      await this.worktreeManager.removeWorktree(workspace, repo, worktreeName);
      return {
        statusCode: 200,
        body: {
          workspace,
          repo,
          worktree: worktreeName,
          status: 'deleted'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private handleGetWorktreePath(workspace: string, repo: string, worktreeName: string): TunnelResponse {
    try {
      const worktreePath = this.worktreeManager.getWorktreePath(workspace, repo, worktreeName);
      return {
        statusCode: 200,
        body: {
          workspace,
          repo,
          worktree: worktreeName,
          path: worktreePath
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }
}
