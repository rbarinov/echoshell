/**
 * Structured logging utility for tunnel-server
 * Outputs JSON-formatted logs with context
 */

type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';

interface LogContext {
  [key: string]: unknown;
}

/**
 * Structured logger with JSON output
 */
export class Logger {
  private static level: LogLevel = (process.env.LOG_LEVEL as LogLevel) || 'INFO';

  /**
   * Log debug message (only in DEBUG mode)
   */
  static debug(message: string, context?: LogContext): void {
    if (this.shouldLog('DEBUG')) {
      this.log('DEBUG', message, context);
    }
  }

  /**
   * Log info message
   */
  static info(message: string, context?: LogContext): void {
    this.log('INFO', message, context);
  }

  /**
   * Log warning message
   */
  static warn(message: string, context?: LogContext): void {
    this.log('WARN', message, context);
  }

  /**
   * Log error message
   */
  static error(message: string, context?: LogContext): void {
    this.log('ERROR', message, context);
  }

  /**
   * Internal log method
   */
  private static log(level: LogLevel, message: string, context?: LogContext): void {
    const logEntry: Record<string, unknown> = {
      timestamp: new Date().toISOString(),
      level,
      message,
    };

    if (context) {
      logEntry.context = this.sanitize(context);
    }

    console.log(JSON.stringify(logEntry));
  }

  /**
   * Sanitize context to remove secrets
   */
  private static sanitize(context: LogContext): LogContext {
    const sanitized = { ...context };
    const secretKeys = [
      'apiKey',
      'api_key',
      'token',
      'password',
      'authKey',
      'auth_key',
      'secret',
      'registrationApiKey',
      'clientAuthKey',
    ];

    secretKeys.forEach((key) => {
      if (sanitized[key]) {
        sanitized[key] = '***';
      }
    });

    return sanitized;
  }

  /**
   * Check if log level should be logged
   */
  private static shouldLog(level: LogLevel): boolean {
    const levels: LogLevel[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
    return levels.indexOf(level) >= levels.indexOf(this.level);
  }

  /**
   * Set log level
   */
  static setLevel(level: LogLevel): void {
    this.level = level;
  }
}
