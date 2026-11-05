import Foundation
import CryptoKit

/// Hash the exact payload bytes, so integrity checks do not depend on JSON re-encoding.
public enum ArchiveCodec {
    private struct Envelope: Codable {
        let checksum: String
        let payload: Data
    }
    public static func encode(_ archive: ExchangeArchive) throws -> Data {
        let payload = try archive.encoded()
        let checksum = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return try ExchangeCoding.encoder().encode(Envelope(checksum: checksum, payload: payload))
    }
    public static func decode(_ data: Data) throws -> ExchangeArchive {
        guard data.count <= 70_000_000 else { throw LearningError.invalid("文件过大，未导入。") }
        let envelope = try ExchangeCoding.decoder().decode(Envelope.self, from: data)
        let checksum = SHA256.hash(data: envelope.payload).map { String(format: "%02x", $0) }.joined()
        guard checksum == envelope.checksum else { throw LearningError.invalid("文件完整性检查失败，未导入。") }
        return try ExchangeArchive.decode(envelope.payload)
    }
}
