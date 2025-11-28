import { Router } from 'express';
import type { TerminalManager } from '../terminal/TerminalManager';
import type { ChatHistoryDatabase } from '../database/ChatHistoryDatabase';
import { CreateTerminalRequestSchema, RenameSessionRequestSchema } from '../schemas/terminalSchemas';
import { z } from 'zod';

export function createTerminalRoutes(terminalManager: TerminalManager, chatHistoryDb?: ChatHistoryDatabase): Router {
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
      const session = terminalManager.getSession(sessionId);

      // If session exists in memory, use it
      if (session) {
        // For headless terminals, return chat history from in-memory state
        if (session.terminalType === 'cursor' || session.terminalType === 'claude') {
          if (!session.chatHistory) {
            console.log(`⚠️ [Express] GET /terminal/${sessionId}/history - Chat history not initialized`);
            return res.json({
              session_id: sessionId,
              chat_history: [],
              history: ''
            });
          }

          const messageCount = session.chatHistory.messages.length;
          console.log(`📂 [Express] GET /terminal/${sessionId}/history - Returning ${messageCount} messages from in-memory history`);

          return res.json({
            session_id: sessionId,
            chat_history: session.chatHistory.messages,
            history: ''
          });
        }

        // For regular terminals, return text history
        const history = terminalManager.getHistory(sessionId);
        return res.json({
          session_id: sessionId,
          history
        });
      }

      // Session not in memory - try to load from database
      if (chatHistoryDb) {
        const dbHistory = chatHistoryDb.getChatHistory(sessionId);
        if (dbHistory) {
          console.log(`📂 [Express] GET /terminal/${sessionId}/history - Session not in memory, loaded ${dbHistory.messages.length} messages from DB`);
          return res.json({
            session_id: sessionId,
            chat_history: dbHistory.messages,
            history: ''
          });
        }
      }

      // No session in memory and no history in DB
      console.log(`⚠️ [Express] GET /terminal/${sessionId}/history - Session not found (not in memory or DB)`);
      return res.status(404).json({ error: 'Session not found' });
    } catch (error) {
      console.error(`❌ [Express] Error getting history for ${req.params.sessionId}:`, error);
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

  router.post('/:sessionId/cancel', (req, res) => {
    try {
      const { sessionId } = req.params;
      console.log(`🛑 [Express] POST /terminal/${sessionId}/cancel - Cancelling current command`);
      terminalManager.cancelCommand(sessionId);
      res.json({
        session_id: sessionId,
        status: 'cancelled'
      });
    } catch (error) {
      console.error(`❌ [Express] Error cancelling command:`, error);
      res.status(500).json({ error: 'Failed to cancel command' });
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
