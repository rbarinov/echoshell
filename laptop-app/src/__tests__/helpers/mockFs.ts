import { jest } from '@jest/globals';

export function createMockFs() {
  const mockFs = {
    mkdir: jest.fn(),
    readdir: jest.fn(),
    stat: jest.fn(),
    readFile: jest.fn(),
    writeFile: jest.fn(),
    unlink: jest.fn(),
    rmdir: jest.fn(),
  };

  return mockFs;
}

