export interface WorkspaceState {
  name: string;
  path: string;
  createdAt: number;
  repositories: RepositoryState[];
}

export interface RepositoryState {
  name: string;
  path: string;
  remoteUrl?: string;
  clonedAt: number;
  worktrees: WorktreeState[];
}

export interface WorktreeState {
  name: string;
  path: string;
  branch: string;
  createdAt: number;
}

