import Foundation

/// Codable control-message envelope sent over the reliable Multipeer channel.
public struct NotchShareMessage: Codable, Equatable {
    public enum Kind: String, Codable {
        case tokenExchange   // payload = archived NIDiscoveryToken
        case ready           // Mac -> iPhone: notch zone entered, open the picker
        case cancel
        case ack             // Mac -> iPhone: file(s) received
        case near            // iPhone -> Mac: BLE proximity entered (glow)
        case far             // iPhone -> Mac: left proximity
    }

    public var kind: Kind
    public var payload: Data?

    public init(_ kind: Kind, payload: Data? = nil) {
        self.kind = kind
        self.payload = payload
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> NotchShareMessage {
        try JSONDecoder().decode(NotchShareMessage.self, from: data)
    }
}
