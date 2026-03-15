import Foundation

public enum OOTAssetID {
    public static func stableID(for symbol: String) -> UInt32 {
        let normalized = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "")

        var hash: UInt32 = 2_166_136_261
        for byte in normalized.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return hash
    }
}
