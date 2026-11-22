import Foundation

/// A sourced dictionary-form reference, not a prediction of a sentence's melody.
public struct WordPitchAccent: Codable, Equatable {
    public let reading: String
    public let morae: [String]
    /// Zero means no lexical downstep; n means a downstep after mora n.
    public let dropAfter: Int
    public let dialect: String
    public let citations: [ContentCitation]

    public var isValid: Bool {
        !morae.isEmpty && morae.allSatisfy { !$0.isEmpty } && morae.joined() == reading &&
        (0...morae.count).contains(dropAfter) && !dialect.isEmpty && !citations.isEmpty
    }
    public var markedReading: String {
        morae.enumerated().map { index, mora in mora + (index + 1 == dropAfter ? "↓" : "") }.joined()
    }
    public var patternName: String {
        if dropAfter == 0 { return "平板型" }
        if dropAfter == 1 { return "头高型" }
        if dropAfter == morae.count { return "尾高型" }
        return "中高型"
    }
    public var explanation: String {
        dropAfter == 0 ? "没有词汇性下降" : "第 \(dropAfter) 拍后下降"
    }
}
