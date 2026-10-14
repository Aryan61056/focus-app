import Foundation

/// What the phone can ask the Mac to do. The Mac decides whether to do it: a refused command is not an error.
public enum Command: Codable, Equatable, Sendable {
    case start(task: String, minutes: Int?)
    case pause, resume, end, takeBreak, backToTask
    case extend(minutes: Int)
}

public enum CommandResult: Codable, Equatable, Sendable {
    case done
    case refused(reason: String)
}

/// Everything sent after the handshake, inside the encrypted channel.
public enum LinkMessage: Codable, Equatable, Sendable {
    case state(SessionState)
    case insights(Insights)
    case command(id: UInt32, Command)
    case result(id: UInt32, CommandResult)
    case requestState
    case requestInsights
}

public enum LinkCoding {
    public static func encode(_ m: some Encodable) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return try e.encode(m)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return try d.decode(type, from: data)
    }
}
