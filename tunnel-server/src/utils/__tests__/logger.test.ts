/**
 * Tests for Logger
 */

import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { Logger } from '../logger';

describe('Logger', () => {
  let consoleLogSpy: jest.SpiedFunction<typeof console.log>;

  beforeEach(() => {
    consoleLogSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    Logger.setLevel('DEBUG');
  });

  afterEach(() => {
    consoleLogSpy.mockRestore();
  });

  it('should log debug messages when level is DEBUG', () => {
    Logger.setLevel('DEBUG');
    Logger.debug('Test debug message', { key: 'value' });
    expect(consoleLogSpy).toHaveBeenCalledTimes(1);
    const logCall = consoleLogSpy.mock.calls[0][0];
    const logData = JSON.parse(logCall as string);
    expect(logData.level).toBe('DEBUG');
    expect(logData.message).toBe('Test debug message');
    expect(logData.context).toEqual({ key: 'value' });
  });

  it('should not log debug messages when level is INFO', () => {
    Logger.setLevel('INFO');
    Logger.debug('Test debug message');
    expect(consoleLogSpy).not.toHaveBeenCalled();
  });

  it('should log info messages', () => {
    Logger.info('Test info message', { key: 'value' });
    expect(consoleLogSpy).toHaveBeenCalledTimes(1);
    const logCall = consoleLogSpy.mock.calls[0][0];
    const logData = JSON.parse(logCall as string);
    expect(logData.level).toBe('INFO');
    expect(logData.message).toBe('Test info message');
    expect(logData.context).toEqual({ key: 'value' });
  });

  it('should log warn messages', () => {
    Logger.warn('Test warn message', { key: 'value' });
    expect(consoleLogSpy).toHaveBeenCalledTimes(1);
    const logCall = consoleLogSpy.mock.calls[0][0];
    const logData = JSON.parse(logCall as string);
    expect(logData.level).toBe('WARN');
    expect(logData.message).toBe('Test warn message');
  });

  it('should log error messages', () => {
    Logger.error('Test error message', { key: 'value' });
    expect(consoleLogSpy).toHaveBeenCalledTimes(1);
    const logCall = consoleLogSpy.mock.calls[0][0];
    const logData = JSON.parse(logCall as string);
    expect(logData.level).toBe('ERROR');
    expect(logData.message).toBe('Test error message');
  });

  it('should sanitize secrets in context', () => {
    Logger.info('Test message', {
      apiKey: 'secret-key',
      password: 'secret-password',
      token: 'secret-token',
      normalKey: 'normal-value',
    });
    expect(consoleLogSpy).toHaveBeenCalledTimes(1);
    const logCall = consoleLogSpy.mock.calls[0][0];
    const logData = JSON.parse(logCall as string);
    expect(logData.context.apiKey).toBe('***');
    expect(logData.context.password).toBe('***');
    expect(logData.context.token).toBe('***');
    expect(logData.context.normalKey).toBe('normal-value');
  });

  it('should include timestamp in logs', () => {
    Logger.info('Test message');
    expect(consoleLogSpy).toHaveBeenCalledTimes(1);
    const logCall = consoleLogSpy.mock.calls[0][0];
    const logData = JSON.parse(logCall as string);
    expect(logData.timestamp).toBeDefined();
    expect(new Date(logData.timestamp)).toBeInstanceOf(Date);
  });
});
