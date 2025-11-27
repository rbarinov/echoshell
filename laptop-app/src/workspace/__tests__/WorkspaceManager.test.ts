import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';
import { WorkspaceManager } from '../WorkspaceManager.js';
import fs from 'fs/promises';
import path from 'path';
import { tmpdir } from 'os';

describe('WorkspaceManager', () => {
  let workspaceManager: WorkspaceManager;
  let testRootPath: string;

  beforeEach(async () => {
    // Create a temporary directory for testing
    testRootPath = path.join(tmpdir(), `echoshell-test-${Date.now()}`);
    workspaceManager = new WorkspaceManager(testRootPath);
    await workspaceManager.initialize();
  });

  afterEach(async () => {
    // Cleanup: remove test directory
    try {
      await fs.rm(testRootPath, { recursive: true, force: true });
    } catch (error) {
      // Ignore cleanup errors
    }
  });

  describe('initialize', () => {
    it('should create root work directory if it does not exist', async () => {
      const newPath = path.join(tmpdir(), `echoshell-test-init-${Date.now()}`);
      const manager = new WorkspaceManager(newPath);
      await manager.initialize();

      const stats = await fs.stat(newPath);
      expect(stats.isDirectory()).toBe(true);

      // Cleanup
      await fs.rm(newPath, { recursive: true, force: true });
    });
  });

  describe('createWorkspace', () => {
    it('should create a new workspace with valid name', async () => {
      const workspace = await workspaceManager.createWorkspace('test-workspace');
      
      expect(workspace.name).toBe('test-workspace');
      expect(workspace.path).toBe(path.join(testRootPath, 'test-workspace'));
      
      const stats = await fs.stat(workspace.path);
      expect(stats.isDirectory()).toBe(true);
    });

    it('should throw error for empty workspace name', async () => {
      await expect(workspaceManager.createWorkspace('')).rejects.toThrow();
    });

    it('should normalize workspace name with special characters', async () => {
      // WorkspaceManager normalizes names, so 'test/workspace' becomes 'testworkspace'
      const workspace = await workspaceManager.createWorkspace('test/workspace');
      expect(workspace.name).toBe('testworkspace');
    });

    it('should throw error if workspace already exists', async () => {
      await workspaceManager.createWorkspace('existing-workspace');
      await expect(workspaceManager.createWorkspace('existing-workspace')).rejects.toThrow();
    });
  });

  describe('listWorkspaces', () => {
    it('should return empty array when no workspaces exist', async () => {
      const workspaces = await workspaceManager.listWorkspaces();
      expect(workspaces).toEqual([]);
    });

    it('should list all created workspaces', async () => {
      await workspaceManager.createWorkspace('workspace1');
      await workspaceManager.createWorkspace('workspace2');
      
      const workspaces = await workspaceManager.listWorkspaces();
      expect(workspaces.length).toBe(2);
      expect(workspaces.map(w => w.name)).toContain('workspace1');
      expect(workspaces.map(w => w.name)).toContain('workspace2');
    });
  });

  describe('cloneRepository', () => {
    it('should throw error if workspace does not exist', async () => {
      await expect(
        workspaceManager.cloneRepository('nonexistent', 'https://github.com/user/repo')
      ).rejects.toThrow();
    });

    // Note: Actual git clone tests would require a real repository or mocking
    // This is a basic structure test
  });

  describe('getWorkspacePath', () => {
    it('should return correct workspace path', () => {
      const workspacePath = workspaceManager.getWorkspacePath('my-workspace');
      expect(workspacePath).toBe(path.join(testRootPath, 'my-workspace'));
    });
  });

  describe('getRepositoryPath', () => {
    it('should return correct repository path', () => {
      const repoPath = workspaceManager.getRepositoryPath('my-workspace', 'my-repo');
      expect(repoPath).toBe(path.join(testRootPath, 'my-workspace', 'my-repo'));
    });
  });
});

