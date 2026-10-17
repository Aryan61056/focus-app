import Foundation

/// A length-prefixed frame: four bytes (big endian) of length, then that many bytes. TCP delivers a stream, not messages.
public enum FrameCodec {
    public static let maxFrame = 1 << 20
    /// Before a peer has proved who it is, it may only send handshake-sized frames.
    public static let maxHandshakeFrame = 16 * 1024

    public static func frame(_ payload: Data) -> Data {
        var d = Data()
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { d.append(contentsOf: $0) }
        return d + payload
    }
}

/// Collects bytes as they arrive and hands back whole frames.
public struct FrameReader: Sendable {
    public struct TooLarge: Error {}
    private var buffer = Data()
    public var maxFrame: Int
    public init(maxFrame: Int = FrameCodec.maxFrame) { self.maxFrame = maxFrame }

    public mutating func append(_ data: Data) { buffer.append(data) }

    public mutating func next() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard length <= maxFrame else { throw TooLarge() }
        guard buffer.count >= 4 + length else { return nil }
        let start = buffer.startIndex + 4
        let payload = Data(buffer[start..<start + length])
        buffer = Data(buffer[(start + length)...])
        return payload
    }
}
