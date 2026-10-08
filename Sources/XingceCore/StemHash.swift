import Foundation
import CryptoKit

enum StemNormalizer {
    static func hash(_ stem: String) -> String {
        let normalized = normalize(stem)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func normalize(_ stem: String) -> String {
        let compatibility = stem.precomposedStringWithCompatibilityMapping.lowercased()
        var scalars: [Unicode.Scalar] = []
        for scalar in compatibility.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            if scalar == "\u{200B}" || scalar == "\u{FEFF}" || scalar == "\u{3000}" {
                continue
            }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func stableToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Za-z0-9._-]{1,80}$"#
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return trimmed
        }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "h" + String(hex.prefix(20))
    }

    static func internalQuestionID(source: String, sourceQuestionID: String?, stemHash: String) -> String {
        let sourceToken = stableToken(source)
        if let sourceQuestionID = sourceQuestionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceQuestionID.isEmpty {
            return "q.\(sourceToken).\(stableToken(sourceQuestionID))"
        }
        return "q.\(sourceToken).stem.\(stemHash.prefix(20))"
    }
}
