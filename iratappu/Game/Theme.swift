import SwiftUI

// MARK: - 設計 token（docs/redesign/UI-SPEC.md 第 1 節）

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let ink = Color(hex: 0x1C1014)
    static let paper = Color.white
    static let hot = Color(hex: 0xFF5548)
    static let cool = Color(hex: 0xCDEFE8)
    static let spark = Color(hex: 0xFFD43B)
    static let woodBg = Color(hex: 0xFFF1CC)
    static let wood = Color(hex: 0x8A5200)
    static let glass = Color.white.opacity(0.72)

    private static let coolRGB = (r: 0xCD / 255.0, g: 0xEF / 255.0, b: 0xE8 / 255.0)
    private static let hotRGB = (r: 0xFF / 255.0, g: 0x55 / 255.0, b: 0x48 / 255.0)

    /// 背景熱度：cool 到 hot 的 sRGB 插值（0...1）
    static func heatColor(_ h: Double) -> Color {
        let t = min(max(h, 0), 1)
        return Color(.sRGB,
                     red: coolRGB.r + (hotRGB.r - coolRGB.r) * t,
                     green: coolRGB.g + (hotRGB.g - coolRGB.g) * t,
                     blue: coolRGB.b + (hotRGB.b - coolRGB.b) * t,
                     opacity: 1)
    }

    /// 原型以 402pt 寬為基準的 pt 值，依容器寬度等比換算（限制在 0.85...1.3，避免 iPad 爆大）
    static let baseWidth: CGFloat = 402

    static func scale(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return min(max(width / baseWidth, 0.85), 1.3)
    }
}

// MARK: - 等比換算

private struct UIScaleKey: EnvironmentKey {
    static var defaultValue: CGFloat { 1 }
}

extension EnvironmentValues {
    /// 容器寬 / 402（1.0 = iPhone 17 Pro）；由 ContentView 依視窗寬度設定
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

private struct UIFont: ViewModifier {
    @Environment(\.uiScale) private var k
    let size: CGFloat
    let weight: Font.Weight
    let number: Bool

    func body(content: Content) -> some View {
        if number {
            content.font(.system(size: size * k, weight: weight, design: .rounded).monospacedDigit())
        } else {
            content.font(.system(size: size * k, weight: weight))
        }
    }
}

extension View {
    /// 規格上的 pt 字級（以 402pt 寬為準，自動換算）。number = 數字用的 rounded + monospacedDigit。
    func uiFont(_ size: CGFloat, _ weight: Font.Weight = .bold, number: Bool = false) -> some View {
        modifier(UIFont(size: size, weight: weight, number: number))
    }
}

// MARK: - 底部 sheet 的共通樣式（UI-SPEC 第 3 節）

struct SheetHeader: View {
    @Environment(\.uiScale) private var k
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .uiFont(36, .black)
                .foregroundColor(Theme.ink)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Text("✕")
                    .uiFont(16, .bold)
                    .foregroundColor(Theme.ink)
                    .frame(width: 44 * k, height: 44 * k)
                    .background(Circle().fill(Theme.ink.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("close_label"))
        }
    }
}

/// 說明文字（lab）
struct SheetLab: View {
    let text: String
    var body: some View {
        Text(text)
            .uiFont(15, .bold)
            .foregroundColor(Theme.ink.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 標題列 + 內容的捲動容器。內距：上下 31、左右 26，區塊間距 18。
struct SheetScaffold<Content: View>: View {
    @Environment(\.uiScale) private var k
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18 * k) {
                SheetHeader(title: title) { dismiss() }
                content()
            }
            .padding(.horizontal, 26 * k)
            .padding(.vertical, 31 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundColor(Theme.ink)
        .presentationCornerRadius(34)
        .presentationBackground(Theme.paper)
        .preferredColorScheme(.light)
    }
}
