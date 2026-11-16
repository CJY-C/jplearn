import SwiftUI
import LearningCore

struct PitchAccentView: View {
    let accents: [WordPitchAccent]
    var detailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(accents.enumerated()), id: \.offset) { _, accent in
                Text("\(accent.markedReading) [\(accent.dropAfter)] · \(accent.patternName)" + (detailed ? "" : " · \(accent.dialect)"))
                    .font(detailed ? .callout.weight(.medium) : .caption.weight(.medium))
                    .accessibilityLabel("\(accent.reading)，\(accent.patternName)，\(accent.explanation)")
                if detailed {
                    Text("\(accent.dialect)参考型 · \(accent.explanation)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if detailed {
                Text("↓ 表示该拍后下降，[0] 表示没有词汇性下降。这是辞书形参考，不是整句固定音高。合成朗读不作为本型的标准示范。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.accessibilityIdentifier("word.pitchAccent")
    }
}
