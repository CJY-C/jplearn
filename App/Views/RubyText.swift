import SwiftUI
import CoreText
import LearningCore

struct RubyText: View {
    let segments: [RubySegment]
    var showReading = true
    var pointSize: CGFloat = 23
    var emphasizedItemID: String? = nil
    var onWord: ((String) -> Void)?
    @State private var height: CGFloat = 60
    @Environment(\.sizeCategory) private var sizeCategory
    var body: some View {
        RubyRepresentable(segments: segments, showReading: showReading, height: $height,
                          sizeCategory: sizeCategory, pointSize: pointSize,
                          emphasizedItemID: emphasizedItemID, onWord: onWord)
            .frame(height: height)
    }
}

private struct RubyRepresentable: UIViewRepresentable {
    let segments: [RubySegment]
    let showReading: Bool
    @Binding var height: CGFloat
    let sizeCategory: ContentSizeCategory
    let pointSize: CGFloat
    let emphasizedItemID: String?
    let onWord: ((String) -> Void)?

    func makeUIView(context: Context) -> RubyLabel { RubyLabel() }
    func updateUIView(_ view: RubyLabel, context: Context) {
        view.configure(segments: segments, showReading: showReading, pointSize: pointSize,
                       emphasizedItemID: emphasizedItemID)
        view.onWord = onWord
        let binding = $height
        view.onHeight = { value in if abs(binding.wrappedValue - value) > 1 { binding.wrappedValue = value } }
        view.setNeedsLayout()
    }
}

private final class RubyLabel: UIView {
    private var attributed = NSAttributedString(string: "")
    private var links: [(NSRange, String)] = []
    private var measuredHeight: CGFloat = 0
    var onHeight: ((CGFloat) -> Void)?
    var onWord: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLanguage = "ja-JP"
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(segments: [RubySegment], showReading: Bool, pointSize: CGFloat, emphasizedItemID: String?) {
        let string = NSMutableAttributedString(string: "")
        links = []
        let font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: UIFont.systemFont(ofSize: pointSize))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 12
        for segment in segments {
            let emphasized = emphasizedItemID != nil && segment.itemID == emphasizedItemID
            let color = emphasized ? (UIColor(named: "AccentColor") ?? UIColor.systemTeal) : UIColor.label
            let range = NSRange(location: string.length, length: (segment.text as NSString).length)
            let text = NSMutableAttributedString(string: segment.text, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ])
            if showReading, let reading = segment.reading, !reading.isEmpty {
                let ruby = CTRubyAnnotationCreateWithAttributes(.auto, .auto, .before, reading as CFString,
                    [kCTRubyAnnotationSizeFactorAttributeName as String: 0.5,
                     kCTForegroundColorAttributeName as String: color.cgColor] as CFDictionary)
                text.addAttribute(NSAttributedString.Key(kCTRubyAnnotationAttributeName as String),
                                  value: ruby, range: NSRange(location: 0, length: text.length))
            }
            string.append(text)
            if let itemID = segment.itemID { links.append((range, itemID)) }
        }
        attributed = string
        accessibilityLabel = segments.map(\.text).joined()
        accessibilityHint = "词语释义也可在下方的词语列表中查看"
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 8 else { return }
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: bounds.width - 8, height: .greatestFiniteMagnitude), nil)
        let nextHeight = ceil(size.height) + 18
        if abs(nextHeight - measuredHeight) > 1 {
            measuredHeight = nextHeight
            DispatchQueue.main.async { [weak self] in self?.onHeight?(nextHeight) }
        }
    }
    private func textFrame() -> CTFrame {
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 4, y: 0, width: max(1, bounds.width - 8), height: max(1, bounds.height - 5)), transform: nil)
        return CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(textFrame(), context)
        context.restoreGState()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsDisplay()
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let location = CGPoint(x: point.x, y: bounds.height - point.y)
        let frame = textFrame()
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let origin = origins[index]
            guard location.y >= origin.y - descent, location.y <= origin.y + ascent + 12,
                  location.x >= origin.x, location.x <= origin.x + CGFloat(width) else { continue }
            let offset = CTLineGetStringIndexForPosition(line, CGPoint(x: location.x - origin.x, y: 0))
            if let link = links.first(where: { NSLocationInRange(offset, $0.0) }) { onWord?(link.1) }
        }
    }
}
