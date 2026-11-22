import Foundation

public struct SpeechVoiceOption: Identifiable, Equatable {
    public enum Quality: Int {
        case standard, enhanced, premium
    }
    public let id: String
    public let name: String
    public let language: String
    public let quality: Quality

    public init(id: String, name: String, language: String, quality: Quality) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }
    public var isJapanese: Bool {
        let code = language.lowercased().replacingOccurrences(of: "_", with: "-")
        return code == "ja" || code.hasPrefix("ja-")
    }
}

public enum SpeechVoiceSelection {
    public static func ordered(_ voices: [SpeechVoiceOption]) -> [SpeechVoiceOption] {
        voices.filter(\.isJapanese).sorted {
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
    }
    public static func preferred(_ voices: [SpeechVoiceOption], selectedID: String = "") -> SpeechVoiceOption? {
        let choices = ordered(voices)
        return choices.first { $0.id == selectedID } ?? choices.first
    }
}
