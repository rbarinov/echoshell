import { jest } from '@jest/globals';

export function createMockGit() {
  const mockExec = jest.fn();
  return mockExec;
}

