import Foundation

/// 規則數值全部集中在這裡，真機調整只改這個檔。
enum GameConfig {
    // MARK: 連擊
    /// 與上一下間隔小於這個秒數算連擊。規格建議改 0.8，真機決定。
    static let comboWindow: TimeInterval = 0.6
    /// 傷害倍率：由大到小比對，連擊 >= combo 就用 factor。
    static let comboMultipliers: [(combo: Int, factor: Double)] = [(60, 3), (30, 2), (10, 1.5)]
    /// 熱度滿值的連擊數
    static let heatMaxCombo = 60
    /// 每幾連擊顯示一次「N 連擊！」
    static let milestoneInterval = 50
    /// 怒氣等級門檻（連擊數）：中怒 / 暴怒 / Max / ProMax
    static let rageThresholds = (mid: 20, high: 40, max: 50, promax: 60)

    // MARK: 對手
    static let baseHP = 60.0
    static let hpPerRun = 30.0
    static let maxNormalHP = 300.0
    static let bossHPFactor = 2.0
    /// 以已擊退數 % 4 循環：普通 / 鐵頭 / 普通 / 魔王
    static let enemyCycle: [EnemyKind] = [.normal, .armor, .normal, .boss]
    /// 鐵頭戴著頭盔時，普通點擊的傷害比例
    static let armorDamageFactor = 0.4

    // MARK: 傷害與力道（力道只影響特效/聲音/震動）
    static let tapDamage = 2.0
    static let swipeDamage = 5.0
    static let chargeDamage = 6.0
    static let critDamage = 10.0
    /// 爆擊一下加的連擊數（含基本的 +1）
    static let critComboBonus = 3
    static let tapPower = 1.0
    static let swipePower = 1.5
    static let chargePower = 1.7
    static let critPower = 2.0
    static let mokugyoPower = 0.5

    // MARK: 弱點
    static let weakSpotChance = 0.1
    /// 這一輪已打超過幾下才可能出現
    static let weakSpotMinTaps = 6
    static let weakSpotLife: TimeInterval = 1.7
    static let weakSpotRadiusFraction = 0.16      // 相對畫面寬
    static let weakSpotX = (min: 0.2, span: 0.6)  // 相對寬
    static let weakSpotY = (min: 0.34, span: 0.38) // 相對高

    // MARK: 手勢
    static let swipeDistanceFraction = 0.16       // 相對寬
    static let swipeMaxDuration: TimeInterval = 0.45
    static let moveCancelFraction = 0.06
    static let chargeStartDelay: TimeInterval = 0.22
    /// 蓄力放開：按住至少幾秒 → 幾下（由大到小比對）
    static let chargeTiers: [(hold: TimeInterval, hits: Int)] = [(3, 5), (2, 3), (1, 2)]
    static let chargeMinHold: TimeInterval = 1.0
    static let chargeHitInterval: TimeInterval = 0.09
    static let chargeScatter = 40.0
    /// 蓄力環滿的秒數
    static let chargeRingFull: TimeInterval = 3.0

    // MARK: 節奏
    static let koGrace: TimeInterval = 0.35
    static let idleToCooling: TimeInterval = 1.0
    static let coolingDuration: TimeInterval = 2.0

    // MARK: 角色
    static let totalCharacters = 18
    static let initialUnlocked = 3

    // MARK: 武器解鎖（只在憤怒模式累計）
    /// 正式門檻（規格 5.2）
    static let weaponThresholds: [WeaponID: Int] = [.slipper: 30, .hammer: 50, .bolt: 20, .kb: 20, .bubble: 2000]
    /// 原型用的小門檻，方便測試
    static let prototypeWeaponThresholds: [WeaponID: Int] = [.slipper: 5, .hammer: 5, .bolt: 3, .kb: 3, .bubble: 80]
    #if DEBUG
    /// DEBUG 專用：true 時改用原型門檻（預設關閉）
    static let useDebugThresholds = false
    #endif

    static func unlockThreshold(for id: WeaponID) -> Int {
        #if DEBUG
        if useDebugThresholds { return prototypeWeaponThresholds[id] ?? 0 }
        #endif
        return weaponThresholds[id] ?? 0
    }

    // MARK: 計算
    static func enemyKind(forRun run: Int) -> EnemyKind {
        enemyCycle[((run % enemyCycle.count) + enemyCycle.count) % enemyCycle.count]
    }

    static func hp(forRun run: Int, kind: EnemyKind) -> Double {
        let base = min(baseHP + hpPerRun * Double(run), maxNormalHP)
        return kind == .boss ? base * bossHPFactor : base
    }

    static func multiplier(forCombo combo: Int) -> Double {
        comboMultipliers.first { combo >= $0.combo }?.factor ?? 1
    }

    static func heat(forCombo combo: Int) -> Double {
        0.3 + 0.7 * Double(min(max(combo, 0), heatMaxCombo)) / Double(heatMaxCombo)
    }

    static func chargeHits(forHold hold: TimeInterval) -> Int {
        chargeTiers.first { hold >= $0.hold }?.hits ?? 0
    }

    static func rageLevel(forCombo combo: Int) -> RageLevel {
        if combo >= rageThresholds.promax { return .promax }
        if combo >= rageThresholds.max { return .max }
        if combo >= rageThresholds.high { return .high }
        if combo >= rageThresholds.mid { return .mid }
        return .calm
    }
}

enum RageLevel: Int, Equatable {
    case calm, mid, high, max, promax
}
