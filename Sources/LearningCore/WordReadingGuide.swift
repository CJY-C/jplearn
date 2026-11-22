import Foundation

/// Use literal kana as anchors. Never invent per-character readings for a
/// kanji cluster or choose arbitrarily between multiple possible alignments.
public enum WordReadingGuide {
    public static func segments(text: String, reading: String, itemID: String? = nil) -> [RubySegment] {
        guard !text.isEmpty else { return [] }
        guard !reading.isEmpty else { return [RubySegment(text: text, reading: nil, itemID: itemID)] }
        func isKana(_ char: Character) -> Bool {
            char.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) ||
                (0x30A1...0x30FA).contains($0.value) || $0.value == 0x30FC }
        }
        var runs: [(text: String, kana: Bool)] = []
        for char in text {
            let kana = isKana(char)
            if runs.last?.kana == kana { runs[runs.count - 1].text.append(char) }
            else { runs.append((String(char), kana)) }
        }
        let sound = Array(AnswerChecker.normalizeKana(reading))
        var matches: [[RubySegment]] = []
        var remainingVisits = 4096
        func align(_ index: Int, _ offset: Int, _ result: [RubySegment]) {
            guard matches.count < 2, remainingVisits > 0 else { return }
            remainingVisits -= 1
            if index == runs.count {
                if offset == sound.count { matches.append(result) }
                return
            }
            let run = runs[index]
            if run.kana {
                let anchor = Array(AnswerChecker.normalizeKana(run.text))
                guard offset + anchor.count <= sound.count,
                      Array(sound[offset..<(offset + anchor.count)]) == anchor else { return }
                align(index + 1, offset + anchor.count,
                      result + [RubySegment(text: run.text, reading: nil, itemID: itemID)])
            } else if offset < sound.count {
                for end in (offset + 1)...sound.count {
                    align(index + 1, end, result + [RubySegment(text: run.text,
                        reading: String(sound[offset..<end]), itemID: itemID)])
                    if matches.count > 1 { return }
                }
            }
        }
        // Malformed or extremely long external inputs should not create a
        // combinatorial search. Whole-word ruby remains a valid fallback.
        if text.count <= 40 && sound.count <= 80 { align(0, 0, []) }
        return matches.count == 1 && remainingVisits > 0 ? matches[0] : [RubySegment(text: text, reading: reading, itemID: itemID)]
    }
}
