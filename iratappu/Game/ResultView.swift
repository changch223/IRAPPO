import SwiftUI

/// 結算頁（覆蓋層，不用 sheet，這樣全螢幕廣告才能從 root 顯示）。
/// 白色面板從下方滑上來，後面的舞台變暗 30%。
struct ResultView: View {
    let summary: RunSummary
    /// 這一輪新解鎖的武器
    var newWeapons: [Weapon] = []
    var reduceMotion = false
    /// 選了心情（0 還是很氣 / 1 好一點 / 2 爽了）
    var onMood: (Int) -> Void = { _ in }
    let onAgain: () -> Void
    /// 心情選了「爽了」時通知（外層決定要不要請求評分）
    let onFeelingBetter: () -> Void

    @Environment(\.uiScale) private var k
    @ObservedObject private var crops = FaceCrop.shared
    @State private var selectedMood: Int?
    @State private var shown = false

    private var moku: Bool { summary.mode == .mokugyo }

    private var title: String {
        if moku { return L("result_title_merit") }
        return L(summary.koCount > 0 ? "result_title_ko" : "result_title_zero")
    }

    private var recordText: String? {
        var parts: [String] = []
        if let c = summary.newBestCombo { parts.append(String(format: L("record_combo"), c)) }
        if let r = summary.newBestRun { parts.append(String(format: L("record_run"), r)) }
        guard !parts.isEmpty else { return nil }
        return String(format: L("result_new_record"), parts.joined(separator: L("record_separator")))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 暗色遮罩：蓋到上方與左右的 safe area，底部停在面板底（也就是 banner 上緣）
            Color.black.opacity(shown ? 0.3 : 0)
                .ignoresSafeArea(edges: [.top, .horizontal])
            ViewThatFits(in: .vertical) {
                panel
                ScrollView { panel }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .background(alignment: .bottom) {
                UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34)
                    .fill(Theme.paper)
            }
            .offset(y: shown || reduceMotion ? 0 : 1200)
            .opacity(shown || !reduceMotion ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.38)) { shown = true }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18 * k) {
            Text(title)
                .uiFont(36, .black)
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8 * k) {
                if moku {
                    stat(L("result_merit"), "\(summary.merit)")
                } else {
                    stat(L("result_ko"), "\(summary.koCount)")
                    stat(L("result_maxcombo"), "\(summary.maxCombo)")
                }
                stat(L("result_taps"), "\(summary.taps)")
                stat(L("result_seconds"), "\(summary.seconds)")
            }

            if let record = recordText {
                Text(record)
                    .uiFont(16, .black)
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 12 * k).padding(.vertical, 6 * k)
                    .background(RoundedRectangle(cornerRadius: 12 * k).fill(Theme.spark))
            }

            if let last = summary.unlockedCharacters.last {
                UnlockCard(title: L("result_unlock_title"), subtitle: L("result_unlock_next"),
                           reduceMotion: reduceMotion) {
                    FaceCrop.image(named: "face\(last + 1)")
                        .resizable().scaledToFit()
                }
            }
            ForEach(newWeapons) { w in
                UnlockCard(title: L("result_weapon_title"), subtitle: w.name, reduceMotion: reduceMotion) {
                    Text(w.emoji).font(.system(size: 44 * k))
                }
            }

            Text(L(selectedMood == nil ? "result_mood_question" : "result_mood_saved"))
                .uiFont(15, .bold)
                .foregroundColor(Theme.ink.opacity(0.65))

            HStack(spacing: 7 * k) {
                moodButton(0, "😤", L("mood_bad"))
                moodButton(1, "😮‍💨", L("mood_ok"))
                moodButton(2, "😌", L("mood_good"))
            }

            Button(action: onAgain) {
                Text(L(moku ? "again_moku" : "again"))
                    .uiFont(21, .black)
                    .foregroundColor(Theme.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56 * k)
                    .background(RoundedRectangle(cornerRadius: 13 * k).fill(Theme.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26 * k)
        .padding(.top, 31 * k)
        .padding(.bottom, 31 * k)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2 * k) {
            Text(value)
                .uiFont(30, .black, number: true)
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .uiFont(15, .bold)
                .foregroundColor(Theme.ink.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func moodButton(_ index: Int, _ emoji: String, _ label: String) -> some View {
        let selected = selectedMood == index
        return Button {
            selectedMood = index
            onMood(index)
            if index == 2 { onFeelingBetter() }
        } label: {
            VStack(spacing: 3 * k) {
                Text(emoji).font(.system(size: 23 * k))
                Text(label)
                    .uiFont(15, .bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10 * k)
            .background(RoundedRectangle(cornerRadius: 13 * k).fill(selected ? Theme.cool : Theme.ink.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 13 * k).stroke(selected ? Theme.ink : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 新角色 / 新武器的卡片：圖從全黑、0.7 倍、-20° 轉成正常（0.9s，延遲 0.3s）
private struct UnlockCard<Art: View>: View {
    let title: String
    let subtitle: String
    let reduceMotion: Bool
    @ViewBuilder let art: () -> Art
    @Environment(\.uiScale) private var k
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 14 * k) {
            art()
                .frame(width: 65 * k, height: 65 * k)
                .brightness(revealed || reduceMotion ? 0 : -1)
                .opacity(revealed || reduceMotion ? 1 : 0.3)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.7)
                .rotationEffect(.degrees(revealed || reduceMotion ? 0 : -20))
            VStack(alignment: .leading, spacing: 2 * k) {
                Text(title).uiFont(18, .black)
                Text(subtitle).uiFont(14, .bold).opacity(0.7)
            }
            .foregroundColor(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10 * k)
        .padding(.horizontal, 14 * k)
        .background(RoundedRectangle(cornerRadius: 18 * k).fill(Theme.cool))
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.9).delay(0.3)) { revealed = true }
        }
    }
}
