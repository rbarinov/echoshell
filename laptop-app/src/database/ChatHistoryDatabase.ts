import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import os from 'os';
import type { ChatMessage, ChatHistory } from '../terminal/types';

/**
 * SQLite database for persistent chat history storage
 * Stores chat messages for headless terminal sessions
 *
 * Features:
 * - Automatic cleanup on app restart (old sessions)
 * - Manual cleanup when session is closed
 * - Full chat history persistence
 */
export class ChatHistoryDatabase {
  private db: Database.Database;
  private dbPath: string;

  constructor(dbPath?: string) {
    // Default path: ~/.echoshell/chat_history.db
    this.dbPath = dbPath || path.join(os.homedir(), '.echoshell', 'chat_history.db');

    // Ensure directory exists
    const dbDir = path.dirname(this.dbPath);
    if (!fs.existsSync(dbDir)) {
      fs.mkdirSync(dbDir, { recursive: true });
    }

    // Open database connection
    this.db = new Database(this.dbPath);

    // Enable WAL mode for better concurrency
    this.db.pragma('journal_mode = WAL');

    // Initialize schema
    this.initializeSchema();

    console.log(`✅ [ChatHistoryDatabase] Initialized at ${this.dbPath}`);
  }

  /**
   * Initialize database schema
   * Creates tables if they don't exist
   */
  private initializeSchema(): void {
    // Chat sessions table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS chat_sessions (
        session_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        closed_at INTEGER DEFAULT NULL,
        is_active INTEGER DEFAULT 1
      )
    `);

    // Chat messages table
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        metadata TEXT DEFAULT NULL,
        FOREIGN KEY (session_id) REFERENCES chat_sessions(session_id) ON DELETE CASCADE
      )
    `);

    // Create indexes for better performance
    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_messages_session_timestamp
      ON chat_messages(session_id, timestamp);
    `);

    this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_sessions_active
      ON chat_sessions(is_active);
    `);

    console.log('✅ [ChatHistoryDatabase] Schema initialized');
  }

  /**
   * Create or update a chat session
   */
  createSession(sessionId: string): void {
    const now = Date.now();

    const stmt = this.db.prepare(`
      INSERT INTO chat_sessions (session_id, created_at, updated_at, is_active)
      VALUES (?, ?, ?, 1)
      ON CONFLICT(session_id) DO UPDATE SET
        updated_at = ?,
        is_active = 1,
        closed_at = NULL
    `);

    stmt.run(sessionId, now, now, now);

    console.log(`✅ [ChatHistoryDatabase] Session created/updated: ${sessionId}`);
  }

  /**
   * Add a message to chat history
   */
  addMessage(sessionId: string, message: ChatMessage): void {
    // Ensure session exists
    this.createSession(sessionId);

    // Insert message
    const stmt = this.db.prepare(`
      INSERT OR REPLACE INTO chat_messages (id, session_id, timestamp, type, content, metadata)
      VALUES (?, ?, ?, ?, ?, ?)
    `);

    const metadataJson = message.metadata ? JSON.stringify(message.metadata) : null;

    stmt.run(
      message.id,
      sessionId,
      message.timestamp,
      message.type,
      message.content,
      metadataJson
    );

    // Update session timestamp
    this.updateSessionTimestamp(sessionId);

    console.log(`✅ [ChatHistoryDatabase] Message added to session ${sessionId}: ${message.type}`);
  }

  /**
   * Get chat history for a session
   */
  getChatHistory(sessionId: string): ChatHistory | null {
    // Check if session exists
    const sessionStmt = this.db.prepare(`
      SELECT created_at, updated_at FROM chat_sessions WHERE session_id = ?
    `);
    const session = sessionStmt.get(sessionId) as { created_at: number; updated_at: number } | undefined;

    if (!session) {
      return null;
    }

    // Get all messages for session
    const messagesStmt = this.db.prepare(`
      SELECT id, timestamp, type, content, metadata
      FROM chat_messages
      WHERE session_id = ?
      ORDER BY timestamp ASC
    `);

    const rows = messagesStmt.all(sessionId) as Array<{
      id: string;
      timestamp: number;
      type: string;
      content: string;
      metadata: string | null;
    }>;

    const messages: ChatMessage[] = rows.map(row => ({
      id: row.id,
      timestamp: row.timestamp,
      type: row.type as ChatMessage['type'],
      content: row.content,
      metadata: row.metadata ? JSON.parse(row.metadata) : undefined
    }));

    return {
      sessionId,
      messages,
      createdAt: session.created_at,
      updatedAt: session.updated_at
    };
  }

  /**
   * Update session timestamp
   */
  private updateSessionTimestamp(sessionId: string): void {
    const stmt = this.db.prepare(`
      UPDATE chat_sessions SET updated_at = ? WHERE session_id = ?
    `);
    stmt.run(Date.now(), sessionId);
  }

  /**
   * Close a session (mark as inactive)
   * This DOES NOT delete the history immediately
   */
  closeSession(sessionId: string): void {
    const stmt = this.db.prepare(`
      UPDATE chat_sessions
      SET is_active = 0, closed_at = ?
      WHERE session_id = ?
    `);
    stmt.run(Date.now(), sessionId);

    console.log(`✅ [ChatHistoryDatabase] Session closed: ${sessionId}`);
  }

  /**
   * Clear chat history for a session (keep session, remove messages)
   * This is used for context reset in agent mode
   */
  clearHistory(sessionId: string): void {
    // Delete messages but keep session
    const deleteMessagesStmt = this.db.prepare(`
      DELETE FROM chat_messages WHERE session_id = ?
    `);
    const messagesDeleted = deleteMessagesStmt.run(sessionId);

    // Update session timestamp
    this.updateSessionTimestamp(sessionId);

    console.log(`✅ [ChatHistoryDatabase] History cleared for session ${sessionId} (${messagesDeleted.changes} messages removed)`);
  }

  /**
   * Delete chat history for a session
   * This permanently removes all messages
   */
  deleteSession(sessionId: string): void {
    // Delete messages (cascade will happen automatically)
    const deleteMessagesStmt = this.db.prepare(`
      DELETE FROM chat_messages WHERE session_id = ?
    `);
    const messagesDeleted = deleteMessagesStmt.run(sessionId);

    // Delete session
    const deleteSessionStmt = this.db.prepare(`
      DELETE FROM chat_sessions WHERE session_id = ?
    `);
    const sessionDeleted = deleteSessionStmt.run(sessionId);

    console.log(`✅ [ChatHistoryDatabase] Session deleted: ${sessionId} (${messagesDeleted.changes} messages removed)`);
  }

  /**
   * Cleanup old closed sessions (on app restart)
   * Deletes sessions that were closed before app restart
   */
  cleanupOldSessions(): void {
    // Get all closed sessions
    const stmt = this.db.prepare(`
      SELECT session_id FROM chat_sessions WHERE is_active = 0
    `);
    const closedSessions = stmt.all() as Array<{ session_id: string }>;

    if (closedSessions.length === 0) {
      console.log('✅ [ChatHistoryDatabase] No old sessions to cleanup');
      return;
    }

    // Delete each closed session
    for (const session of closedSessions) {
      this.deleteSession(session.session_id);
    }

    console.log(`✅ [ChatHistoryDatabase] Cleaned up ${closedSessions.length} old sessions`);
  }

  /**
   * Get list of active sessions
   */
  getActiveSessions(): string[] {
    const stmt = this.db.prepare(`
      SELECT session_id FROM chat_sessions WHERE is_active = 1 ORDER BY updated_at DESC
    `);
    const rows = stmt.all() as Array<{ session_id: string }>;
    return rows.map(row => row.session_id);
  }

  /**
   * Get session statistics
   */
  getSessionStats(sessionId: string): { messageCount: number; createdAt: number; updatedAt: number } | null {
    const stmt = this.db.prepare(`
      SELECT
        COUNT(m.id) as message_count,
        s.created_at,
        s.updated_at
      FROM chat_sessions s
      LEFT JOIN chat_messages m ON s.session_id = m.session_id
      WHERE s.session_id = ?
      GROUP BY s.session_id
    `);

    const result = stmt.get(sessionId) as { message_count: number; created_at: number; updated_at: number } | undefined;

    if (!result) {
      return null;
    }

    return {
      messageCount: result.message_count,
      createdAt: result.created_at,
      updatedAt: result.updated_at
    };
  }

  /**
   * Close database connection
   */
  close(): void {
    this.db.close();
    console.log('✅ [ChatHistoryDatabase] Database connection closed');
  }

  /**
   * Vacuum database to reclaim space
   * Should be called periodically (e.g., on app startup after cleanup)
   */
  vacuum(): void {
    this.db.exec('VACUUM');
    console.log('✅ [ChatHistoryDatabase] Database vacuumed');
  }
}
