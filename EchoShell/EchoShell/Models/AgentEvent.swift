/**
 * Unified Agent Event Protocol (Swift)
 * 
 * Matches the TypeScript AgentEvent schema for consistent communication
 * between iOS ↔ Tunnel Server ↔ Laptop App
 */

import Foundation

// MARK: - AgentEvent Types

enum AgentEventType: String, Codable {
    case commandText = "command_text"
    case commandVoice = "command_voice"
    case transcription = "transcription"
    case assistantMessage = "assistant_message"
    case ttsAudio = "tts_audio"
    case completion = "completion"
    case error = "error"
    case contextReset = "context_reset"
}

// MARK: - Base AgentEvent

struct AgentEvent: Codable {
    let type: AgentEventType
    let sessionId: String
    let messageId: String
    let parentId: String?
    let timestamp: Int64
    let payload: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case messageId = "message_id"
        case parentId = "parent_id"
        case timestamp
        case payload
    }
}

// MARK: - Specific Event Types (Client → Server)

struct CommandTextEvent {
    let sessionId: String
    let text: String
    
    func toAgentEvent() -> AgentEvent {
        return AgentEvent(
            type: .commandText,
            sessionId: sessionId,
            messageId: UUID().uuidString,
            parentId: nil,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: ["text": AnyCodable(text)]
        )
    }
}

struct CommandVoiceEvent {
    let sessionId: String
    let audioBase64: String
    let format: String // "wav", "m4a", "opus"
    
    func toAgentEvent() -> AgentEvent {
        return AgentEvent(
            type: .commandVoice,
            sessionId: sessionId,
            messageId: UUID().uuidString,
            parentId: nil,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "audio_base64": AnyCodable(audioBase64),
                "format": AnyCodable(format)
            ]
        )
    }
}

struct ContextResetEvent {
    let sessionId: String
    
    func toAgentEvent() -> AgentEvent {
        return AgentEvent(
            type: .contextReset,
            sessionId: sessionId,
            messageId: UUID().uuidString,
            parentId: nil,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [:]
        )
    }
}

// MARK: - Specific Event Types (Server → Client)

struct AgentTranscriptionEvent {
    let text: String
    let confidence: Double?
    
    init?(from event: AgentEvent) {
        guard event.type == .transcription else { return nil }
        guard let text = event.payload["text"]?.value as? String else { return nil }
        self.text = text
        self.confidence = event.payload["confidence"]?.value as? Double
    }
}

struct AgentAssistantMessageEvent {
    let content: String
    let isFinal: Bool
    let metadata: AssistantMetadata?
    
    struct AssistantMetadata {
        let toolName: String?
        let toolInput: String?
        let toolOutput: String?
        let thinking: String?
    }
    
    init?(from event: AgentEvent) {
        guard event.type == .assistantMessage else { return nil }
        guard let content = event.payload["content"]?.value as? String else { return nil }
        guard let isFinal = event.payload["is_final"]?.value as? Bool else { return nil }
        
        self.content = content
        self.isFinal = isFinal
        
        if let metadataDict = event.payload["metadata"]?.value as? [String: Any] {
            self.metadata = AssistantMetadata(
                toolName: metadataDict["tool_name"] as? String,
                toolInput: metadataDict["tool_input"] as? String,
                toolOutput: metadataDict["tool_output"] as? String,
                thinking: metadataDict["thinking"] as? String
            )
        } else {
            self.metadata = nil
        }
    }
}

struct AgentTTSAudioEvent {
    let audioBase64: String
    let format: String
    let durationMs: Int
    let transcript: String
    
    init?(from event: AgentEvent) {
        guard event.type == .ttsAudio else { return nil }
        guard let audioBase64 = event.payload["audio_base64"]?.value as? String else { return nil }
        guard let format = event.payload["format"]?.value as? String else { return nil }
        guard let durationMs = event.payload["duration_ms"]?.value as? Int else { return nil }
        guard let transcript = event.payload["transcript"]?.value as? String else { return nil }
        
        self.audioBase64 = audioBase64
        self.format = format
        self.durationMs = durationMs
        self.transcript = transcript
    }
}

struct AgentCompletionEvent {
    let success: Bool
    let result: String?
    let error: String?
    
    init?(from event: AgentEvent) {
        guard event.type == .completion else { return nil }
        guard let success = event.payload["success"]?.value as? Bool else { return nil }
        
        self.success = success
        self.result = event.payload["result"]?.value as? String
        self.error = event.payload["error"]?.value as? String
    }
}

struct AgentErrorEvent {
    let code: String
    let message: String
    let details: [String: Any]?
    
    init?(from event: AgentEvent) {
        guard event.type == .error else { return nil }
        guard let code = event.payload["code"]?.value as? String else { return nil }
        guard let message = event.payload["message"]?.value as? String else { return nil }
        
        self.code = code
        self.message = message
        self.details = event.payload["details"]?.value as? [String: Any]
    }
}

// MARK: - AnyCodable Helper

// Wrapper to encode/decode dynamic JSON
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        case let array as [Any]:
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        case is NSNull:
            try container.encodeNil()
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Unsupported type: \(type(of: value))"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}

