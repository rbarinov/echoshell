import type { TerminalManager } from '../terminal/TerminalManager';
import type { TunnelRequest, TunnelResponse } from '../types';
import {
  CreateTerminalRequestSchema,
  ExecuteCommandRequestSchema,
  RenameSessionRequestSchema,
  ResizeTerminalRequestSchema
} from '../schemas/terminalSchemas';
import { validateRequest } from '../utils/validation';
import logger from '../utils/logger';

export class TerminalHandler {
  constructor(private terminalManager: TerminalManager) {}

  async handleRequest(req: TunnelRequest): Promise<TunnelResponse> {
    const { method, path } = req;

    if (path === '/terminal/list' && method === 'GET') {
      return this.handleList();
    }

    if (path === '/terminal/create' && method === 'POST') {
      return this.handleCreate(req.body);
    }

    const renameMatch = path.match(/^\/terminal\/([^\/]+)\/rename$/);
    if (renameMatch && method === 'POST') {
      return this.handleRename(renameMatch[1], req.body);
    }

    const historyMatch = path.match(/^\/terminal\/([^\/]+)\/history$/);
    if (historyMatch && method === 'GET') {
      return this.handleHistory(historyMatch[1]);
    }

    const executeMatch = path.match(/^\/terminal\/([^\/]+)\/execute$/);
    if (executeMatch && method === 'POST') {
      return this.handleExecute(executeMatch[1], req.body);
    }

    const resizeMatch = path.match(/^\/terminal\/([^\/]+)\/resize$/);
    if (resizeMatch && method === 'POST') {
      return this.handleResize(resizeMatch[1], req.body);
    }

    const deleteMatch = path.match(/^\/terminal\/([^\/]+)$/);
    if (deleteMatch && method === 'DELETE') {
      return this.handleDelete(deleteMatch[1]);
    }

    return { statusCode: 404, body: { error: 'Not found' } };
  }

  private handleList(): TunnelResponse {
    const sessions = this.terminalManager.listSessions();
    return {
      statusCode: 200,
      body: {
        sessions: sessions.map(s => ({
          session_id: s.sessionId,
          working_dir: s.workingDir,
          terminal_type: s.terminalType,
          name: s.name
        }))
      }
    };
  }

  private async handleCreate(body: unknown): Promise<TunnelResponse> {
    const validation = validateRequest(CreateTerminalRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { terminal_type, working_dir, name } = validation.data;
    const session = await this.terminalManager.createSession(terminal_type, working_dir, name);

    logger.info('Created terminal session', { sessionId: session.sessionId, terminalType: terminal_type });

    return {
      statusCode: 200,
      body: {
        session_id: session.sessionId,
        working_dir: session.workingDir,
        terminal_type: session.terminalType,
        name: session.name,
        status: 'created'
      }
    };
  }

  private handleRename(sessionId: string, body: unknown): TunnelResponse {
    const validation = validateRequest(RenameSessionRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { name } = validation.data;

    try {
      this.terminalManager.renameSession(sessionId, name);
      logger.info('Renamed session', { sessionId, name });
      return {
        statusCode: 200,
        body: {
          session_id: sessionId,
          name,
          status: 'renamed'
        }
      };
    } catch (error) {
      if (error instanceof Error && error.message === 'Session not found') {
        return { statusCode: 404, body: { error: 'Session not found' } };
      }
      return { statusCode: 500, body: { error: 'Failed to rename session' } };
    }
  }

  private handleHistory(sessionId: string): TunnelResponse {
    const history = this.terminalManager.getHistory(sessionId);

    logger.debug('Retrieved history', { sessionId, historyLength: history.length });

    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        history
      }
    };
  }

  private async handleExecute(sessionId: string, body: unknown): Promise<TunnelResponse> {
    const validation = validateRequest(ExecuteCommandRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { command } = validation.data;

    logger.info('Executing command', { sessionId, command });

    try {
      const output = await this.terminalManager.executeCommand(sessionId, command || '');

      logger.debug('Command executed', { sessionId, outputLength: output.length });

      return {
        statusCode: 200,
        body: {
          session_id: sessionId,
          command,
          output
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('Error executing command', error instanceof Error ? error : new Error(errorMessage), { sessionId });

      return {
        statusCode: 200,
        body: {
          session_id: sessionId,
          command,
          output: '',
          error: errorMessage
        }
      };
    }
  }

  private handleResize(sessionId: string, body: unknown): TunnelResponse {
    const validation = validateRequest(ResizeTerminalRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { cols, rows } = validation.data;

    this.terminalManager.resizeTerminal(sessionId, cols, rows);

    logger.info('Resized terminal', { sessionId, cols, rows });

    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        cols,
        rows,
        status: 'resized'
      }
    };
  }

  private async handleDelete(sessionId: string): Promise<TunnelResponse> {
    await this.terminalManager.destroySession(sessionId);

    logger.info('Deleted session', { sessionId });

    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        status: 'deleted'
      }
    };
  }
}
