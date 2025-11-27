import fs from 'fs/promises';
import path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import type { WorkspaceManager } from './WorkspaceManager';
import { normalizeBranchName, normalizeWorktreeName, normalizeRepositoryName } from './nameNormalizer';

const execAsync = promisify(exec);

export interface WorktreeInfo {
  name: string;
  path: string;
  branch: string;
  createdAt: number;
}

export class WorktreeManager {
  private workspaceManager: WorkspaceManager;

  constructor(workspaceManager: WorkspaceManager) {
    this.workspaceManager = workspaceManager;
  }

  async createWorktree(
    workspace: string,
    repo: string,
    branchOrFeature: string,
    worktreeName?: string
  ): Promise<WorktreeInfo> {
    const repoPath = this.workspaceManager.getRepositoryPath(workspace, repo);

    // Verify repository exists
    try {
      const stats = await fs.stat(repoPath);
      if (!stats.isDirectory()) {
        throw new Error(`Repository "${repo}" does not exist in workspace "${workspace}"`);
      }

      // Check if it's a git repository
      const gitPath = path.join(repoPath, '.git');
      await fs.stat(gitPath);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Repository "${repo}" does not exist in workspace "${workspace}"`);
      }
      throw error;
    }

    // Normalize branch/feature name to kebab-case
    const normalizedBranch = normalizeBranchName(branchOrFeature);
    
    // Determine worktree name (use pattern: repo-feature)
    // Normalize both repo name and branch name
    const normalizedRepo = normalizeRepositoryName(repo);
    const finalWorktreeName = normalizeWorktreeName(worktreeName || `${normalizedRepo}-${normalizedBranch}`);
    const worktreePath = path.join(repoPath, finalWorktreeName);

    try {
      // Check if worktree path already exists
      try {
        const stats = await fs.stat(worktreePath);
        if (stats.isDirectory()) {
          throw new Error(`Worktree "${finalWorktreeName}" already exists at ${worktreePath}`);
        }
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
          throw error;
        }
      }

      // Check if branch exists
      let branchExists = false;
      try {
        const { stdout } = await execAsync('git branch -a', {
          cwd: repoPath,
          maxBuffer: 1024 * 1024
        });
        const branches = stdout.split('\n').map(b => b.trim().replace(/^\*\s*/, '').replace(/^remotes\/[^\/]+\//, ''));
        branchExists = branches.some(b => b === branchOrFeature || b.endsWith(`/${branchOrFeature}`));
      } catch (error) {
        console.warn(`⚠️  Could not check branches: ${error}`);
      }

      // Create worktree
      // Use normalized branch name for git commands
      let gitCommand: string;
      if (branchExists) {
        // Use existing branch (check both original and normalized names)
        gitCommand = `git worktree add "${worktreePath}" "${branchOrFeature}"`;
      } else {
        // Create new branch with normalized name
        gitCommand = `git worktree add "${worktreePath}" -b "${normalizedBranch}"`;
      }

      console.log(`🌳 Creating worktree: ${finalWorktreeName} (branch: ${branchOrFeature})...`);
      const { stdout, stderr } = await execAsync(gitCommand, {
        cwd: repoPath,
        maxBuffer: 10 * 1024 * 1024
      });

      if (stderr && !stderr.includes('Preparing worktree')) {
        console.warn(`⚠️  Git worktree warning: ${stderr}`);
      }

      console.log(`✅ Created worktree: ${finalWorktreeName} at ${worktreePath}`);

      // Get creation time
      const stats = await fs.stat(worktreePath);
      const createdAt = stats.birthtimeMs || stats.mtimeMs;

      return {
        name: finalWorktreeName,
        path: worktreePath,
        branch: normalizedBranch, // Return normalized branch name
        createdAt: createdAt
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to create worktree: ${errorMessage}`);
      throw error;
    }
  }

  async listWorktrees(workspace: string, repo: string): Promise<WorktreeInfo[]> {
    const repoPath = this.workspaceManager.getRepositoryPath(workspace, repo);

    // Verify repository exists
    try {
      const stats = await fs.stat(repoPath);
      if (!stats.isDirectory()) {
        throw new Error(`Repository "${repo}" does not exist in workspace "${workspace}"`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Repository "${repo}" does not exist in workspace "${workspace}"`);
      }
      throw error;
    }

    try {
      // Get worktrees using git worktree list
      const { stdout } = await execAsync('git worktree list', {
        cwd: repoPath,
        maxBuffer: 10 * 1024 * 1024
      });

      const worktrees: WorktreeInfo[] = [];
      const lines = stdout.split('\n').filter(line => line.trim().length > 0);

      for (const line of lines) {
        // Parse git worktree list output format:
        // /path/to/worktree  [branch-name]
        // or
        // /path/to/worktree  [branch-name] (detached HEAD)
        const match = line.match(/^(.+?)\s+\[(.+?)\]/);
        if (match) {
          const worktreePath = match[1].trim();
          const branch = match[2].trim();

          // Only include worktrees that are in the repo directory (not the main repo)
          if (worktreePath !== repoPath && worktreePath.startsWith(repoPath)) {
            const worktreeName = path.basename(worktreePath);
            try {
              const stats = await fs.stat(worktreePath);
              const createdAt = stats.birthtimeMs || stats.mtimeMs;
              worktrees.push({
                name: worktreeName,
                path: worktreePath,
                branch: branch,
                createdAt: createdAt
              });
            } catch (error) {
              // Skip worktrees we can't stat
              console.warn(`⚠️  Could not stat worktree ${worktreePath}:`, error);
            }
          }
        }
      }

      return worktrees.sort((a, b) => a.name.localeCompare(b.name));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to list worktrees: ${errorMessage}`);
      throw error;
    }
  }

  async removeWorktree(workspace: string, repo: string, worktreeName: string): Promise<void> {
    const repoPath = this.workspaceManager.getRepositoryPath(workspace, repo);
    const worktreePath = path.join(repoPath, worktreeName);

    // Verify worktree exists
    try {
      const stats = await fs.stat(worktreePath);
      if (!stats.isDirectory()) {
        throw new Error(`Worktree "${worktreeName}" does not exist`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Worktree "${worktreeName}" does not exist`);
      }
      throw error;
    }

    try {
      console.log(`🗑️  Removing worktree: ${worktreeName}...`);
      const { stdout, stderr } = await execAsync(`git worktree remove "${worktreePath}"`, {
        cwd: repoPath,
        maxBuffer: 10 * 1024 * 1024
      });

      if (stderr && !stderr.includes('Removing')) {
        console.warn(`⚠️  Git worktree remove warning: ${stderr}`);
      }

      console.log(`✅ Removed worktree: ${worktreeName}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to remove worktree: ${errorMessage}`);
      throw error;
    }
  }

  getWorktreePath(workspace: string, repo: string, worktreeName: string): string {
    return path.join(this.workspaceManager.getRepositoryPath(workspace, repo), worktreeName);
  }

  async validateWorktree(workspace: string, repo: string, worktreeName: string): Promise<boolean> {
    const worktreePath = this.getWorktreePath(workspace, repo, worktreeName);

    try {
      const stats = await fs.stat(worktreePath);
      if (!stats.isDirectory()) {
        return false;
      }

      // Check if it's a valid git worktree (has .git file or directory)
      const gitPath = path.join(worktreePath, '.git');
      try {
        await fs.stat(gitPath);
        return true;
      } catch (error) {
        return false;
      }
    } catch (error) {
      return false;
    }
  }
}

