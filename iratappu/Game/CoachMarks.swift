import SwiftUI

/// 在地化字串的簡寫
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

// MARK: - 情境提示：做到就消失，每個最多出現兩次

enum CoachKey: String, CaseIterable {
    case tap, swipe, armor, hold, weak

    var text: String { L("coach_\(rawValue)") }

    var icon: String {
        switch self {
        case .tap, .weak: return "👆"
        case .swipe, .armor: return "👉"
        case .hold: return "👇"
        }
    }

    /// 圖示動畫：點＝按壓、滑＝橫移、長按＝壓住不放
    var animation: CoachAnimation {
        switch self {
        case .tap, .weak: return .press
        case .swipe, .armor: return .slide
        case .hold: return .hold
        }
    }

    /// 顯示多久後自動消失（秒）
    var duration: TimeInterval { self == .tap ? 60 : 6 }
}

enum CoachAnimation { case press, slide, hold, none }

/// 一次性的訊息提示（如「解鎖武器：XXX」，key＝`w-<id>`），高優先、不計次數
struct CoachMessage: Equatable {
    let key: String
    let icon: String
    let text: String
}

enum CoachConfig {
    static let maxShows = 2
}

final class CoachManager: ObservableObject {
    @Published private(set) var current: CoachKey?
    @Published private(set) var message: CoachMessage?
    private var timer: Timer?
    private var messageTimer: Timer?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func doneKey(_ k: CoachKey) -> String { "coach.\(k.rawValue).done" }
    private func countKey(_ k: CoachKey) -> String { "coach.\(k.rawValue).shows" }

    func isDone(_ k: CoachKey) -> Bool { defaults.bool(forKey: doneKey(k)) }

    /// 武器解鎖等訊息：插隊顯示 6 秒，只在發生當下出現一次
    func showMessage(_ m: CoachMessage, duration: TimeInterval = 6) {
        messageTimer?.invalidate()
        message = m
        messageTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.message = nil
        }
    }

    /// force：高優先（鐵頭、弱點）可以插隊
    func show(_ k: CoachKey, force: Bool = false) {
        if isDone(k) || current == k { return }
        if current != nil && !force { return }
        timer?.invalidate()
        current = k
        // 顯示當下就算一次；第 maxShows 次顯示時立刻標記完成，之後永不再出現
        // （不靠計時器：提示可能被 hide() 提前收掉）
        let shows = defaults.integer(forKey: countKey(k)) + 1
        defaults.set(shows, forKey: countKey(k))
        if shows >= CoachConfig.maxShows { defaults.set(true, forKey: doneKey(k)) }
        timer = Timer.scheduledTimer(withTimeInterval: k.duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    /// 做到了：永久不再出現
    func done(_ k: CoachKey) {
        defaults.set(true, forKey: doneKey(k))
        if current == k { hide() }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        if current != nil { current = nil }
    }

    /// 解鎖訊息有自己的壽命（6 秒計時）；hide() / done() 都不會動它。
    func hideMessage() {
        messageTimer?.invalidate()
        messageTimer = nil
        if message != nil { message = nil }
    }

    /// 只有指定的提示正在顯示時才收起
    func hide(ifShowing k: CoachKey) {
        if current == k { hide() }
    }
}

/// 舞台底部的膠囊：ink 底、白字，不蓋打擊區、不攔截觸控。
struct CoachCapsule: View {
    @ObservedObject var coach: CoachManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiScale) private var k
    @State private var phase = false

    private var item: (id: String, icon: String, text: String, anim: CoachAnimation)? {
        if let m = coach.message { return (m.key, m.icon, m.text, .none) }
        if let c = coach.current { return (c.rawValue, c.icon, c.text, c.animation) }
        return nil
    }

    var body: some View {
        ZStack {
            if let item {
                HStack(spacing: 8 * k) {
                    Text(item.icon)
                        .font(.system(size: 26 * k))
                        .offset(x: offsetX(item.anim), y: offsetY(item.anim))
                        .scaleEffect(scale(item.anim))
                    Text(item.text)
                        .uiFont(18, .bold)
                        .foregroundColor(Theme.paper)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.leading, 12 * k)
                .padding(.trailing, 17 * k)
                .padding(.vertical, 8 * k)
                .background(Capsule().fill(Theme.ink))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(item.id)
                .onAppear {
                    phase = false
                    guard !reduceMotion, item.anim != .none else { return }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { phase = true }
                }
            }
        }
        .padding(.horizontal, 12 * k)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: item?.id)
        .allowsHitTesting(false)
    }

    private func offsetX(_ a: CoachAnimation) -> CGFloat { a == .slide ? (phase ? 8 : -8) : 0 }
    private func offsetY(_ a: CoachAnimation) -> CGFloat { a == .press ? (phase ? 4 : -2) : 0 }
    private func scale(_ a: CoachAnimation) -> CGFloat { a == .hold ? (phase ? 0.85 : 1.0) : 1.0 }
}
