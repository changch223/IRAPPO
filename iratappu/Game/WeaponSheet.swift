import SwiftUI

/// 武器選單：未解鎖的灰階並顯示解鎖條件、進度與細進度條
struct WeaponSheet: View {
    @ObservedObject var progress: WeaponProgress
    let selected: String
    let onSelect: (WeaponID) -> Void
    @Environment(\.uiScale) private var k

    var body: some View {
        SheetScaffold(title: L("weapon_sheet_title")) {
            VStack(spacing: 8 * k) {
                ForEach(Weapons.all) { w in
                    row(w)
                }
            }
            SheetLab(text: L("weapon_footer"))
        }
    }

    private func row(_ w: Weapon) -> some View {
        let unlocked = progress.isUnlocked(w.id)
        let on = selected == w.id.rawValue
        return Button {
            if unlocked { onSelect(w.id) }
        } label: {
            HStack(spacing: 14 * k) {
                Text(w.emoji)
                    .font(.system(size: 39 * k))
                    .grayscale(unlocked ? 0 : 1)
                    .opacity(unlocked ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2 * k) {
                    Text(w.name).uiFont(19, .black)
                    if unlocked || w.unlock == nil {
                        Text(w.desc).uiFont(15, .regular).opacity(0.7)
                    } else if let req = w.unlock {
                        let p = progress.progress(for: w)
                        Text(String(format: L("weapon_unlock_progress"), L(req.stat.labelKey), p.current, p.required))
                            .uiFont(15, .regular).opacity(0.7)
                        // 細進度條
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.ink.opacity(0.12))
                                Capsule().fill(Theme.ink)
                                    .frame(width: geo.size.width * CGFloat(p.current) / CGFloat(max(p.required, 1)))
                            }
                        }
                        .frame(height: 5 * k)
                        .padding(.top, 3 * k)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(Theme.ink)
            .padding(.vertical, 12 * k)
            .padding(.horizontal, 14 * k)
            .background(RoundedRectangle(cornerRadius: 16 * k).fill(on ? Theme.cool : Theme.ink.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16 * k).stroke(on ? Theme.ink : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
