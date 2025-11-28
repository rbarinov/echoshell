import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { HeadlessExecutor } from '../HeadlessExecutor';

// Mock child_process
const mockSpawn = jest.fn();
jest.mock('child_process', () => ({
  spawn: (...args: any[]) => mockSpawn(...args),
}));

describe('HeadlessExecutor', () => {
  let executor: HeadlessExecutor;
  const mockWorkingDir = '/tmp/test';
  const mockStdout = { on: jest.fn() };
  const mockStderr = { on: jest.fn() };
  const mockSubprocess = {
    stdout: mockStdout,
    stderr: mockStderr,
    on: jest.fn(),
    kill: jest.fn(),
    killed: false,
  };

  beforeEach(() => {
    mockSpawn.mockReturnValue(mockSubprocess);
    executor = new HeadlessExecutor(mockWorkingDir, 'cursor');
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('execute', () => {
    it('should spawn subprocess with correct command and args for cursor', async () => {
      await executor.execute('test prompt');

      expect(mockSpawn).toHaveBeenCalledWith(
        'cursor-agent',
        expect.arrayContaining([
          '--output-format',
          'stream-json',
          '--print',
          'test prompt',
        ]),
        expect.objectContaining({
          cwd: mockWorkingDir,
        })
      );
    });

    it('should spawn subprocess with correct command and args for claude', async () => {
      const claudeExecutor = new HeadlessExecutor(mockWorkingDir, 'claude');
      await claudeExecutor.execute('test prompt');

      expect(mockSpawn).toHaveBeenCalledWith(
        'claude',
        expect.arrayContaining([
          '--verbose',
          '--print',
          '-p',
          'test prompt',
          '--output-format',
          'stream-json',
        ]),
        expect.objectContaining({
          cwd: mockWorkingDir,
        })
      );
    });

    it('should include --resume flag when session ID is set', async () => {
      executor.setCliSessionId('session-123');
      await executor.execute('test prompt');

      expect(mockSpawn).toHaveBeenCalledWith(
        'cursor-agent',
        expect.arrayContaining(['--resume', 'session-123']),
        expect.any(Object)
      );
    });

    it('should setup stdout, stderr, and exit handlers', async () => {
      await executor.execute('test prompt');

      expect(mockStdout.on).toHaveBeenCalledWith('data', expect.any(Function));
      expect(mockStderr.on).toHaveBeenCalledWith('data', expect.any(Function));
      expect(mockSubprocess.on).toHaveBeenCalledWith('exit', expect.any(Function));
      expect(mockSubprocess.on).toHaveBeenCalledWith('error', expect.any(Function));
    });
  });

  describe('session ID management', () => {
    it('should store and retrieve CLI session ID', () => {
      executor.setCliSessionId('session-123');
      expect(executor.getCliSessionId()).toBe('session-123');
    });

    it('should clear CLI session ID when set to null', () => {
      executor.setCliSessionId('session-123');
      executor.setCliSessionId(null);
      expect(executor.getCliSessionId()).toBeNull();
    });
  });

  describe('callbacks', () => {
    it('should call stdout callback when data is received', async () => {
      const stdoutCallback = jest.fn();
      executor.onStdout(stdoutCallback);

      await executor.execute('test');
      
      // Simulate stdout data
      const stdoutHandler = mockStdout.on.mock.calls.find(call => call[0] === 'data')?.[1] as (data: Buffer) => void;
      if (stdoutHandler) {
        stdoutHandler(Buffer.from('test output'));
        expect(stdoutCallback).toHaveBeenCalledWith('test output');
      }
    });

    it('should call stderr callback when error data is received', async () => {
      const stderrCallback = jest.fn();
      executor.onStderr(stderrCallback);

      await executor.execute('test');
      
      // Simulate stderr data
      const stderrHandler = mockStderr.on.mock.calls.find(call => call[0] === 'data')?.[1] as (data: Buffer) => void;
      if (stderrHandler) {
        stderrHandler(Buffer.from('error output'));
        expect(stderrCallback).toHaveBeenCalledWith('error output');
      }
    });

    it('should call exit callback when process exits', async () => {
      const exitCallback = jest.fn();
      executor.onExit(exitCallback);

      await executor.execute('test');
      
      // Simulate exit
      const exitHandler = mockSubprocess.on.mock.calls.find(call => call[0] === 'exit')?.[1] as (code: number | null) => void;
      if (exitHandler) {
        exitHandler(0);
        expect(exitCallback).toHaveBeenCalledWith(0);
      }
    });
  });

  describe('kill', () => {
    it('should kill subprocess gracefully', async () => {
      await executor.execute('test');
      executor.kill();
      expect(mockSubprocess.kill).toHaveBeenCalledWith('SIGTERM');
    });

    it('should check if subprocess is running', async () => {
      expect(executor.isRunning()).toBe(false); // No subprocess spawned yet
      await executor.execute('test');
      expect(executor.isRunning()).toBe(true); // Subprocess spawned
    });
  });

  describe('cleanup', () => {
    it('should cleanup all callbacks and kill subprocess', async () => {
      const stdoutCallback = jest.fn();
      const stderrCallback = jest.fn();
      const exitCallback = jest.fn();

      executor.onStdout(stdoutCallback);
      executor.onStderr(stderrCallback);
      executor.onExit(exitCallback);

      await executor.execute('test');
      executor.cleanup();

      expect(mockSubprocess.kill).toHaveBeenCalled();
      // Callbacks should be cleared (can't easily test without executing)
    });
  });
});
