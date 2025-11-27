import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import { exec } from 'child_process';
import { promisify } from 'util';
import { normalizeWorkspaceName, normalizeRepositoryName } from './nameNormalizer.js';

const execAsync = promisify(exec);

export interface WorkspaceInfo {
  name: string;
  path: string;
  createdAt: number;
}

export interface RepositoryInfo {
  name: string;
  path: string;
  remoteUrl?: string;
  clonedAt: number;
}

export interface ProjectInfo {
  name: string;
  path: string;
  createdAt: number;
}

export class WorkspaceManager {
  private rootPath: string;
  private initialized: boolean = false;

  constructor(rootPath?: string) {
    this.rootPath = rootPath || process.env.WORK_ROOT_PATH || path.join(os.homedir(), 'work');
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      await fs.mkdir(this.rootPath, { recursive: true });
      console.log(`📁 Initialized workspace root: ${this.rootPath}`);
      this.initialized = true;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to initialize workspace root: ${errorMessage}`);
      throw new Error(`Failed to initialize workspace root: ${errorMessage}`);
    }
  }

  getRootPath(): string {
    return this.rootPath;
  }

  async createWorkspace(name: string): Promise<WorkspaceInfo> {
    await this.ensureInitialized();

    // Validate workspace name
    if (!name || name.trim().length === 0) {
      throw new Error('Workspace name cannot be empty');
    }

    // Normalize workspace name to kebab-case (handles transliteration, spaces, etc.)
    const sanitizedName = normalizeWorkspaceName(name);
    if (!sanitizedName || sanitizedName.length === 0) {
      throw new Error('Workspace name cannot be normalized to a valid name');
    }

    const workspacePath = path.join(this.rootPath, sanitizedName);

    try {
      // Check if workspace already exists
      try {
        const stats = await fs.stat(workspacePath);
        if (stats.isDirectory()) {
          throw new Error(`Workspace "${sanitizedName}" already exists`);
        }
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
          throw error;
        }
      }

      await fs.mkdir(workspacePath, { recursive: true });
      console.log(`✅ Created workspace: ${sanitizedName} at ${workspacePath}`);

      return {
        name: sanitizedName,
        path: workspacePath,
        createdAt: Date.now()
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to create workspace: ${errorMessage}`);
      throw error;
    }
  }

  async removeWorkspace(name: string): Promise<void> {
    await this.ensureInitialized();

    const workspacePath = path.join(this.rootPath, name);

    try {
      const stats = await fs.stat(workspacePath);
      if (!stats.isDirectory()) {
        throw new Error(`Workspace "${name}" is not a directory`);
      }

      // Check if workspace is empty (optional: could add force flag)
      const entries = await fs.readdir(workspacePath);
      if (entries.length > 0) {
        throw new Error(`Workspace "${name}" is not empty. Remove repositories first or use force flag.`);
      }

      await fs.rmdir(workspacePath);
      console.log(`✅ Removed workspace: ${name}`);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Workspace "${name}" does not exist`);
      }
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to remove workspace: ${errorMessage}`);
      throw error;
    }
  }

  async cloneRepository(workspace: string, repoUrl: string, repoName?: string): Promise<RepositoryInfo> {
    await this.ensureInitialized();

    const workspacePath = path.join(this.rootPath, workspace);

    // Verify workspace exists
    try {
      const stats = await fs.stat(workspacePath);
      if (!stats.isDirectory()) {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
      throw error;
    }

    // Extract repo name from URL if not provided
    let finalRepoName = repoName;
    if (!finalRepoName) {
      const urlMatch = repoUrl.match(/\/([^\/]+?)(?:\.git)?$/);
      if (urlMatch) {
        finalRepoName = urlMatch[1].replace(/\.git$/, '');
      } else {
        throw new Error('Cannot determine repository name from URL. Please provide repoName parameter.');
      }
    }

    // Normalize repo name to kebab-case (handles transliteration, spaces, etc.)
    const sanitizedRepoName = normalizeRepositoryName(finalRepoName);
    if (!sanitizedRepoName || sanitizedRepoName.length === 0) {
      throw new Error('Repository name cannot be normalized to a valid name');
    }
    const repoPath = path.join(workspacePath, sanitizedRepoName);

    try {
      // Check if repository already exists
      try {
        const stats = await fs.stat(repoPath);
        if (stats.isDirectory()) {
          throw new Error(`Repository "${sanitizedRepoName}" already exists in workspace "${workspace}"`);
        }
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
          throw error;
        }
      }

      // Clone repository
      console.log(`📥 Cloning repository ${repoUrl} into ${repoPath}...`);
      const { stdout, stderr } = await execAsync(`git clone ${repoUrl} ${repoPath}`, {
        cwd: workspacePath,
        maxBuffer: 10 * 1024 * 1024 // 10MB buffer
      });

      if (stderr && !stderr.includes('Cloning into')) {
        console.warn(`⚠️  Git clone warning: ${stderr}`);
      }

      console.log(`✅ Cloned repository: ${sanitizedRepoName} at ${repoPath}`);

      return {
        name: sanitizedRepoName,
        path: repoPath,
        remoteUrl: repoUrl,
        clonedAt: Date.now()
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to clone repository: ${errorMessage}`);
      throw error;
    }
  }

  async listWorkspaces(): Promise<WorkspaceInfo[]> {
    await this.ensureInitialized();

    try {
      const entries = await fs.readdir(this.rootPath);
      const workspaces: WorkspaceInfo[] = [];

      for (const entry of entries) {
        const entryPath = path.join(this.rootPath, entry);
        try {
          const stats = await fs.stat(entryPath);
          if (stats.isDirectory()) {
            // Get creation time (approximate - use mtime if birthtime not available)
            const createdAt = stats.birthtimeMs || stats.mtimeMs;
            workspaces.push({
              name: entry,
              path: entryPath,
              createdAt: createdAt
            });
          }
        } catch (error) {
          // Skip entries we can't stat
          console.warn(`⚠️  Could not stat ${entryPath}:`, error);
        }
      }

      return workspaces.sort((a, b) => a.name.localeCompare(b.name));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to list workspaces: ${errorMessage}`);
      throw error;
    }
  }

  async createProject(workspace: string, projectName: string): Promise<ProjectInfo> {
    await this.ensureInitialized();

    const workspacePath = path.join(this.rootPath, workspace);

    // Verify workspace exists
    try {
      const stats = await fs.stat(workspacePath);
      if (!stats.isDirectory()) {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
      throw error;
    }

    // Normalize project name to kebab-case
    const sanitizedProjectName = normalizeRepositoryName(projectName);
    if (!sanitizedProjectName || sanitizedProjectName.length === 0) {
      throw new Error('Project name cannot be normalized to a valid name');
    }

    const projectPath = path.join(workspacePath, sanitizedProjectName);

    try {
      // Check if project already exists
      try {
        const stats = await fs.stat(projectPath);
        if (stats.isDirectory()) {
          throw new Error(`Project "${sanitizedProjectName}" already exists in workspace "${workspace}"`);
        }
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
          throw error;
        }
      }

      // Create project directory
      await fs.mkdir(projectPath, { recursive: true });
      console.log(`✅ Created project: ${sanitizedProjectName} at ${projectPath}`);

      return {
        name: sanitizedProjectName,
        path: projectPath,
        createdAt: Date.now()
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to create project: ${errorMessage}`);
      throw error;
    }
  }

  async getProjectPath(workspace: string, projectName: string): Promise<string> {
    await this.ensureInitialized();

    const workspacePath = path.join(this.rootPath, workspace);
    const normalizedProjectName = normalizeRepositoryName(projectName);
    const projectPath = path.join(workspacePath, normalizedProjectName);

    // Verify project exists
    try {
      const stats = await fs.stat(projectPath);
      if (!stats.isDirectory()) {
        throw new Error(`Project "${normalizedProjectName}" does not exist in workspace "${workspace}"`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Project "${normalizedProjectName}" does not exist in workspace "${workspace}"`);
      }
      throw error;
    }

    return projectPath;
  }

  async listProjects(workspace: string): Promise<ProjectInfo[]> {
    await this.ensureInitialized();

    const workspacePath = path.join(this.rootPath, workspace);

    // Verify workspace exists
    try {
      const stats = await fs.stat(workspacePath);
      if (!stats.isDirectory()) {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
      throw error;
    }

    try {
      const entries = await fs.readdir(workspacePath);
      const projects: ProjectInfo[] = [];

      for (const entry of entries) {
        const entryPath = path.join(workspacePath, entry);
        try {
          const stats = await fs.stat(entryPath);
          if (stats.isDirectory()) {
            // Check if it's a git repository (has .git folder)
            const gitPath = path.join(entryPath, '.git');
            const isGitRepo = await fs.stat(gitPath).then(() => true).catch(() => false);
            
            // Include both git repos and regular project folders
            const createdAt = stats.birthtimeMs || stats.mtimeMs;
            projects.push({
              name: entry,
              path: entryPath,
              createdAt: createdAt
            });
          }
        } catch (error) {
          // Skip entries we can't stat
          console.warn(`⚠️  Could not stat ${entryPath}:`, error);
        }
      }

      return projects.sort((a, b) => a.name.localeCompare(b.name));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to list projects: ${errorMessage}`);
      throw error;
    }
  }

  async listRepositories(workspace: string): Promise<RepositoryInfo[]> {
    await this.ensureInitialized();

    const workspacePath = path.join(this.rootPath, workspace);

    // Verify workspace exists
    try {
      const stats = await fs.stat(workspacePath);
      if (!stats.isDirectory()) {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        throw new Error(`Workspace "${workspace}" does not exist`);
      }
      throw error;
    }

    try {
      const entries = await fs.readdir(workspacePath);
      const repositories: RepositoryInfo[] = [];

      for (const entry of entries) {
        const entryPath = path.join(workspacePath, entry);
        try {
          const stats = await fs.stat(entryPath);
          if (stats.isDirectory()) {
            // Check if it's a git repository
            const gitPath = path.join(entryPath, '.git');
            try {
              const gitStats = await fs.stat(gitPath);
              if (gitStats.isDirectory() || gitStats.isFile()) {
                // Get remote URL if available
                let remoteUrl: string | undefined;
                try {
                  const { stdout } = await execAsync('git remote get-url origin', {
                    cwd: entryPath,
                    maxBuffer: 1024 * 1024
                  });
                  remoteUrl = stdout.trim();
                } catch (error) {
                  // Remote might not be set, that's okay
                }

                const createdAt = stats.birthtimeMs || stats.mtimeMs;
                repositories.push({
                  name: entry,
                  path: entryPath,
                  remoteUrl,
                  clonedAt: createdAt
                });
              }
            } catch (error) {
              // Not a git repository, skip
            }
          }
        } catch (error) {
          // Skip entries we can't stat
          console.warn(`⚠️  Could not stat ${entryPath}:`, error);
        }
      }

      return repositories.sort((a, b) => a.name.localeCompare(b.name));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ Failed to list repositories: ${errorMessage}`);
      throw error;
    }
  }

  getWorkspacePath(workspace: string): string {
    return path.join(this.rootPath, workspace);
  }

  getRepositoryPath(workspace: string, repo: string): string {
    return path.join(this.rootPath, workspace, repo);
  }

  private async ensureInitialized(): Promise<void> {
    if (!this.initialized) {
      await this.initialize();
    }
  }
}

