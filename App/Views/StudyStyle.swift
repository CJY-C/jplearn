import SwiftUI

struct StudyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundColor(.white)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct StudyQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).frame(minHeight: 44)
            .foregroundColor(.accentColor)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.16 : 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct StudyPressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct StudyIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44).foregroundColor(.accentColor)
            .background(Color(UIColor.secondarySystemBackground).opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(Circle())
    }
}

struct StudyCardLayout<Content: View, Actions: View>: View {
    @Environment(\.sizeCategory) private var sizeCategory
    private let scrolling: Bool
    private let content: (Bool) -> Content
    private let actions: () -> Actions

    init(scrolling: Bool = false, @ViewBuilder content: @escaping (Bool) -> Content,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.scrolling = scrolling; self.content = content; self.actions = actions
    }
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 420
            Group {
                if scrolling || sizeCategory.isAccessibilityCategory {
                    ScrollView { content(compact).padding(.horizontal, 18).padding(.vertical, 12) }
                        .accessibilityIdentifier("study.textScroll")
                } else {
                    content(compact).padding(.horizontal, 18).padding(.vertical, compact ? 8 : 14)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.55)
                actions().padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 12)
            }.background(Color(UIColor.systemBackground))
                .accessibilityIdentifier("study.actions")
        }
    }
}
