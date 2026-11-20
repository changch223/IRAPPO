import Foundation

// MARK: - 武器（只有表現，沒有任何戰鬥數值）
// 規格 5.1：所有武器傷害、判定、連擊時間完全相同。這裡的型別不准放傷害、連擊或時間數值。

enum WeaponID: String, CaseIterable {
    case fist, slipper, hammer, bolt, kb, bubble
}

/// 解鎖統計的種類（只在憤怒模式累計）
enum UnlockStat: String, CaseIterable {
    case swipes, kos, charges, crits, taps

    var labelKey: String { "stat_\(rawValue)" }
}

enum HitEffect: Equatable { case impact, footprint, crack, lightning, keycaps, bubbles }
enum KOEffect: Equatable { case none, footprints, shatter, lightning, keycapRain, bubbleBurst }
enum HapticStyle: Equatable { case scaled, sharp, soft, rumble }

struct WeaponSound: Equatable {
    let hit: String
    let ko: String
    /// 音高是否隨連擊升高
    let pitchesWithCombo: Bool
}

struct UnlockRequirement: Equatable {
    let stat: UnlockStat
}

struct Weapon: Equatable, Identifiable {
    let id: WeaponID
    let emoji: String
    let nameKey: String
    let descKey: String
    let hitEffect: HitEffect
    let koEffect: KOEffect
    let sound: WeaponSound
    let haptic: HapticStyle
    /// 是否晃畫面（表現用，不是戰鬥數值）。泡泡紙刻意保持安靜＝false，所有晃動路徑都要看這個旗標。
    let shakesScreen: Bool
    /// nil＝一開始就有
    let unlock: UnlockRequirement?

    var name: String { L(nameKey) }
    var desc: String { L(descKey) }
}

enum Weapons {
    static let all: [Weapon] = [
        Weapon(id: .fist, emoji: "👊", nameKey: "weapon_fist_name", descKey: "weapon_fist_desc",
               hitEffect: .impact, koEffect: .none,
               sound: WeaponSound(hit: "hit", ko: "boom", pitchesWithCombo: true),
               haptic: .scaled, shakesScreen: true, unlock: nil),
        Weapon(id: .slipper, emoji: "🩴", nameKey: "weapon_slipper_name", descKey: "weapon_slipper_desc",
               hitEffect: .footprint, koEffect: .footprints,
               sound: WeaponSound(hit: "slipper", ko: "boom", pitchesWithCombo: true),
               haptic: .scaled, shakesScreen: true, unlock: UnlockRequirement(stat: .swipes)),
        Weapon(id: .hammer, emoji: "🔨", nameKey: "weapon_hammer_name", descKey: "weapon_hammer_desc",
               hitEffect: .crack, koEffect: .shatter,
               sound: WeaponSound(hit: "hammer", ko: "shatter", pitchesWithCombo: true),
               haptic: .sharp, shakesScreen: true, unlock: UnlockRequirement(stat: .kos)),
        Weapon(id: .bolt, emoji: "⚡", nameKey: "weapon_bolt_name", descKey: "weapon_bolt_desc",
               hitEffect: .lightning, koEffect: .lightning,
               sound: WeaponSound(hit: "bolt", ko: "boom", pitchesWithCombo: false),
               haptic: .rumble, shakesScreen: true, unlock: UnlockRequirement(stat: .charges)),
        Weapon(id: .kb, emoji: "⌨️", nameKey: "weapon_kb_name", descKey: "weapon_kb_desc",
               hitEffect: .keycaps, koEffect: .keycapRain,
               sound: WeaponSound(hit: "kb", ko: "boom", pitchesWithCombo: false),
               haptic: .scaled, shakesScreen: true, unlock: UnlockRequirement(stat: .crits)),
        Weapon(id: .bubble, emoji: "🫧", nameKey: "weapon_bubble_name", descKey: "weapon_bubble_desc",
               hitEffect: .bubbles, koEffect: .bubbleBurst,
               sound: WeaponSound(hit: "bubble", ko: "boom", pitchesWithCombo: true),
               haptic: .soft, shakesScreen: false, unlock: UnlockRequirement(stat: .taps)),
    ]

    static func weapon(_ id: WeaponID) -> Weapon {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - 解鎖進度

final class WeaponProgress: ObservableObject {
    @Published private(set) var counts: [UnlockStat: Int] = [:]
    @Published private(set) var unlocked: Set<WeaponID> = [.fist]

    private let defaults: UserDefaults
    private var dirty = false
    private var timer: Timer?
    static let flushDelay: TimeInterval = 2.0
    private static let unlockedKey = "unlockedWeapons"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for stat in UnlockStat.allCases {
            counts[stat] = defaults.integer(forKey: "weaponStat.\(stat.rawValue)")
        }
        if let raw = defaults.stringArray(forKey: Self.unlockedKey) {
            unlocked.formUnion(raw.compactMap(WeaponID.init(rawValue:)))
        }
    }

    func count(_ stat: UnlockStat) -> Int { counts[stat] ?? 0 }
    func isUnlocked(_ id: WeaponID) -> Bool { unlocked.contains(id) }

    /// 解鎖進度（已累計 / 需要）
    func progress(for weapon: Weapon) -> (current: Int, required: Int) {
        guard let req = weapon.unlock else { return (0, 0) }
        let need = GameConfig.unlockThreshold(for: weapon.id)
        return (min(count(req.stat), need), need)
    }

    /// 累計一筆統計，回傳這次新解鎖的武器。
    @discardableResult
    func record(_ stat: UnlockStat, by n: Int = 1) -> [Weapon] {
        counts[stat, default: 0] += n
        markDirty()
        var gained: [Weapon] = []
        for w in Weapons.all {
            guard let req = w.unlock, req.stat == stat, !unlocked.contains(w.id),
                  count(stat) >= GameConfig.unlockThreshold(for: w.id) else { continue }
            unlocked.insert(w.id)
            gained.append(w)
        }
        if !gained.isEmpty { flush() }
        return gained
    }

    /// 一個遊戲事件會累計哪些統計：只在憤怒模式。
    /// taps＝每一下打擊（含滑、蓄力爆發的每一下）；charges＝蓄力放開一次；swipes/crits/kos 各一次。
    static func increments(for event: GameEvent, mode: GameMode) -> [UnlockStat] {
        guard mode == .rage else { return [] }
        switch event {
        case .hit(let h):
            var r: [UnlockStat] = [.taps]
            if h.kind == .swipe { r.append(.swipes) }
            if h.crit { r.append(.crits) }
            return r
        case .ko:
            return [.kos]
        case .chargeReleased:
            return [.charges]
        default:
            return []
        }
    }

    private func markDirty() {
        dirty = true
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.flushDelay, repeats: false) { [weak self] _ in
            self?.flush()
        }
    }

    func flush() {
        timer?.invalidate()
        timer = nil
        guard dirty else { return }
        dirty = false
        for (stat, n) in counts { defaults.set(n, forKey: "weaponStat.\(stat.rawValue)") }
        defaults.set(unlocked.map(\.rawValue).sorted(), forKey: Self.unlockedKey)
    }
}
