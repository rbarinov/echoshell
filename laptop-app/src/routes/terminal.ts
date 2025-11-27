import { Router } from 'express';
import type { TerminalManager } from '../terminal/TerminalManager';
import { CreateTerminalRequestSchema, RenameSessionRequestSchema } from '../schemas/terminalSchemas';
import { z } from 'zod';

export function createTerminalRoutes(terminalManager: TerminalManager): Router {
  const router = Router();

  router.get('/list', async (_req, res) => {
    try {
      const sessions = terminalManager.listSessions();
      res.json({
        sessions: sessions.map(s => ({
          session_id: s.sessionId,
          working_dir: s.workingDir,
          terminal_type: s.terminalType,
          name: s.name,
          created_at: s.createdAt || Date.now()
        }))
      });
    } catch (error) {
      res.status(500).json({ error: 'Failed to list sessions' });
    }
  });

  router.post('/create', async (req, res) => {
    try {
      const validation = CreateTerminalRequestSchema.safeParse(req.body);
      if (!validation.success) {
        return res.status(400).json({
          error: 'Validation failed',
          details: validation.error.errors
        });
      }
      const { terminal_type, working_dir, name } = validation.data;
      const session = await terminalManager.createSession(terminal_type, working_dir, name);
      res.json({
        session_id: session.sessionId,
        working_dir: session.workingDir,
        terminal_type: session.terminalType,
        name: session.name,
        status: 'created'
      });
    } catch (error) {
      res.status(500).json({ error: 'Failed to create session' });
    }
  });

  router.get('/:sessionId/history', (req, res) => {
    try {
      const { sessionId } = req.params;
      const history = terminalManager.getHistory(sessionId);
      res.json({
        session_id: sessionId,
        history
      });
    } catch (error) {
      res.status(500).json({ error: 'Failed to get history' });
    }
  });

  router.post('/:sessionId/execute', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { command } = req.body;
      console.log(`🌐 [Express] POST /terminal/${sessionId}/execute - Command: ${JSON.stringify(command)}`);
      const output = await terminalManager.executeCommand(sessionId, command || '');
      res.json({
        session_id: sessionId,
        command,
        output
      });
    } catch (error) {
      console.error(`❌ [Express] Error executing command:`, error);
      res.status(500).json({ error: 'Failed to execute command' });
    }
  });

  router.post('/:sessionId/rename', (req, res) => {
    try {
      const { sessionId } = req.params;
      const validation = RenameSessionRequestSchema.safeParse(req.body);
      if (!validation.success) {
        return res.status(400).json({
          error: 'Validation failed',
          details: validation.error.errors
        });
      }
      const { name } = validation.data;
      terminalManager.renameSession(sessionId, name);
      res.json({
        session_id: sessionId,
        name,
        status: 'renamed'
      });
    } catch (error) {
      if (error instanceof Error && error.message === 'Session not found') {
        return res.status(404).json({ error: 'Session not found' });
      }
      res.status(500).json({ error: 'Failed to rename session' });
    }
  });

  router.delete('/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      await terminalManager.destroySession(sessionId);
      res.json({
        session_id: sessionId,
        status: 'deleted'
      });
    } catch (error) {
      res.status(500).json({ error: 'Failed to delete session' });
    }
  });

  return router;
}
