import SwiftUI

enum CareLoopBrandSurface {
    case light
    case dark
}

enum CareLoopBrandStyle {
    case icon
    case wordmark
    case lockup
}

struct CareLoopBrandView: View {
    let style: CareLoopBrandStyle
    var surface: CareLoopBrandSurface = .light
    var iconSize: CGFloat = 28
    var wordmarkHeight: CGFloat = 22
    var spacing: CGFloat = 10

    var body: some View {
        switch style {
        case .icon:
            icon
        case .wordmark:
            wordmark
        case .lockup:
            HStack(spacing: spacing) {
                icon
                wordmark
            }
        }
    }

    private var icon: some View {
        Image("CareLoopIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
    }

    private var wordmark: some View {
        Image(surface == .dark ? "CareLoopWordmarkDark" : "CareLoopWordmarkLight")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: wordmarkHeight)
            .fixedSize()
    }
}

private struct CareLoopBrandToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .principal) {
                CareLoopBrandView(style: .wordmark, surface: .light, wordmarkHeight: 20)
            }
        }
    }
}

extension View {
    func careLoopBrandBanner() -> some View {
        modifier(CareLoopBrandToolbarModifier())
    }
}
