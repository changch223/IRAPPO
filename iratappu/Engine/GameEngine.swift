import Foundation
import CoreGraphics

// MARK: - 型別

enum GameMode: Equatable { case rage, mokugyo }
enum HitKind: Equatable { case tap, swipe, charge }
enum EnemyKind: Equatable { case normal, armor, boss }

struct Enemy: Equatable {
    var kind: EnemyKind
    var characterIndex: Int
    var isNewCharacter: Bool
    /// 第幾個（已擊退數 + 1）
    var ordinal: Int
    var maxHP: Double
    var hp: Double
    var hasArmor: Bool
}

struct WeakSpot: Equatable {
    var center: CGPoint
    var radius: Double
    var until: TimeInterval
}

struct HitEvent: Equatable {
    var kind: HitKind
    var location: CGPoint
    /// 滑動起點（只有 swipe 有意義）
    var from: CGPoint
    /// 滑動方向 +1 右 / -1 左
    var direction: Int
    var damage: Double
    var combo: Int
    var multiplier: Double
    var crit: Bool
    var blocked: Bool
    var power: Double
}

struct KOEvent: Equatable {
    var boss: Bool
    /// 擊退後的累計數（第 N 個）
    var run: Int
    var newCharacter: Bool
    var characterIndex: Int
}

struct RunSummary: Equatable {
    var mode: GameMode
    var koCount: Int
    var taps: Int
    var maxCombo: Int
    var seconds: Int
    var merit: Int
    /// 破最高連擊紀錄（>= 10 才有）
    var newBestCombo: Int?
    var newBestRun: Int?
    var unlockedCharacters: [Int]
}

enum GameEvent: Equatable {
    case runStarted
    case hit(HitEvent)
    case armorOff(at: CGPoint)
    case comboMilestone(Int)
    case weakSpotShown(WeakSpot)
    case weakSpotHidden(hit: Bool)
    case ko(KOEvent)
    case enemySpawned(Enemy, dropped: Bool)
    case characterUnlocked(total: Int)
    case chargingStarted
    case chargingStopped
    /// 蓄力放開（要爆發 hits 下）
    case chargeReleased(hits: Int)
    case coolingStarted
    case coolingCancelled
    case finished(RunSummary)
}

// MARK: - 規則引擎（純 Swift；時間由呼叫端以秒傳入）

final class GameEngine {
    enum Phase: Equatable { case idle, fighting, cooling, finished }
    enum ReleaseResult: Equatable {
        case ignored
        case tap
        case swipe
        case charge(hits: Int, origin: CGPoint)
    }

    var onEvent: ((GameEvent) -> Void)?
    /// 打擊區大小（弱點、滑動距離都以此為基準）
    var stage: CGSize
    /// 弱點只會出現在這個範圍內（畫面層依「可見的臉」設定）。nil＝沿用 GameConfig 的比例範圍。
    var weakSpotArea: CGRect?
    /// 弱點半徑（點）。nil＝沿用 GameConfig 的比例（相對畫面寬）。
    var weakSpotRadius: Double?

    private let random: () -> Double

    private(set) var mode: GameMode = .rage
    private(set) var phase: Phase = .idle
    private(set) var enemy: Enemy
    /// 這一輪已擊退數
    private(set) var run = 0
    private(set) var taps = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var merit = 0
    private(set) var lastHit: TimeInterval?
    private(set) var weakSpot: WeakSpot?
    private(set) var unlockedCount: Int
    private(set) var characterIndex = 0
    var bestCombo = 0
    var bestRun = 0

    private var recordCombo = false
    private var recordRun = false
    private var newlyUnlocked: [Int] = []
    private var nextIsNew = false
    private var startTime: TimeInterval = 0
    private var endTime: TimeInterval = 0
    private var lastActivity: TimeInterval = 0
    private var coolingStart: TimeInterval = 0

    // 按壓狀態
    private(set) var isPressing = false
    private(set) var isCharging = false
    private var pressStart: TimeInterval = 0
    private var pressOrigin: CGPoint = .zero
    private var pressMoved = false
    private var holdKeepsCombo = false

    init(unlockedCount: Int = GameConfig.initialUnlocked,
         stage: CGSize = CGSize(width: 390, height: 600),
         random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.unlockedCount = max(1, min(unlockedCount, GameConfig.totalCharacters))
        self.stage = stage
        self.random = random
        self.enemy = Enemy(kind: .normal, characterIndex: 0, isNewCharacter: false, ordinal: 1,
                           maxHP: GameConfig.baseHP, hp: GameConfig.baseHP, hasArmor: false)
    }

    /// 該不該繼續跑 tick
    var needsTick: Bool {
        isPressing || phase == .fighting || phase == .cooling || weakSpot != nil
    }

    // MARK: - 開新一輪

    func reset(mode: GameMode, characterIndex: Int = 0) {
        self.mode = mode
        phase = .idle
        run = 0; taps = 0; combo = 0; maxCombo = 0; merit = 0
        lastHit = nil
        weakSpot = nil
        recordCombo = false; recordRun = false
        newlyUnlocked = []
        nextIsNew = false
        isPressing = false; isCharging = false; pressMoved = false
        self.characterIndex = min(max(characterIndex, 0), unlockedCount - 1)
        spawn(dropped: false)
    }

    private func spawn(dropped: Bool) {
        let kind: EnemyKind = mode == .rage ? GameConfig.enemyKind(forRun: run) : .normal
        let hp = GameConfig.hp(forRun: run, kind: kind)
        enemy = Enemy(kind: kind, characterIndex: characterIndex, isNewCharacter: nextIsNew,
                      ordinal: run + 1, maxHP: hp, hp: hp, hasArmor: kind == .armor)
        hideWeakSpot(hit: false)
        emit(.enemySpawned(enemy, dropped: dropped))
    }

    // MARK: - 輸入

    func pressBegan(at p: CGPoint, now: TimeInterval) {
        guard phase != .finished else { return }
        wake(now)
        isPressing = true
        isCharging = false
        pressMoved = false
        pressStart = now
        pressOrigin = p
        lastActivity = now
        if let last = lastHit, combo > 0, now - last < GameConfig.comboWindow {
            holdKeepsCombo = true
        } else {
            holdKeepsCombo = false
        }
    }

    func pressMoved(to p: CGPoint, now: TimeInterval) {
        guard isPressing, !pressMoved else { return }
        if hypot(p.x - pressOrigin.x, p.y - pressOrigin.y) > Double(stage.width) * GameConfig.moveCancelFraction {
            pressMoved = true
            if isCharging {
                isCharging = false
                emit(.chargingStopped)
            }
        }
    }

    /// 放開手指：分成 點 / 滑 / 蓄力。蓄力只回傳要打幾下，由呼叫端依間隔呼叫 `chargeHit`。
    @discardableResult
    func pressEnded(at p: CGPoint, now: TimeInterval) -> ReleaseResult {
        guard isPressing else { return .ignored }
        isPressing = false
        let duration = now - pressStart
        let charged = isCharging
        if charged {
            isCharging = false
            emit(.chargingStopped)
        }
        lastActivity = now
        guard phase != .finished else { return .ignored }

        let dx = p.x - pressOrigin.x, dy = p.y - pressOrigin.y
        let dist = hypot(dx, dy)
        if mode == .rage, dist > Double(stage.width) * GameConfig.swipeDistanceFraction,
           duration < GameConfig.swipeMaxDuration {
            hit(kind: .swipe, at: p, now: now, from: pressOrigin, direction: dx >= 0 ? 1 : -1)
            return .swipe
        }
        // 蓄力凍結連擊：放開時先把 lastHit 設成現在，爆發才接著原本連擊往上加
        if charged && combo > 0 { lastHit = now }
        if !charged || duration < GameConfig.chargeMinHold {
            hit(kind: .tap, at: pressOrigin, now: now)
            return .tap
        }
        let hits = GameConfig.chargeHits(forHold: duration)
        emit(.chargeReleased(hits: hits))
        return .charge(hits: hits, origin: pressOrigin)
    }

    /// 觸控被取消（來電、Siri、進背景、系統搶走觸控）：不出手，清掉按壓狀態，之後可以正常冷卻。
    func pressCancelled(now: TimeInterval) {
        guard isPressing else { return }
        isPressing = false
        pressMoved = false
        if isCharging {
            isCharging = false
            emit(.chargingStopped)
        }
        lastActivity = now
    }

    /// 蓄力爆發的其中一下：落點在按壓點周圍隨機。
    func chargeHit(origin: CGPoint, now: TimeInterval) {
        let s = GameConfig.chargeScatter
        let p = CGPoint(x: origin.x + (random() * 2 - 1) * s, y: origin.y + (random() * 2 - 1) * s)
        hit(kind: .charge, at: p, now: now)
    }

    // MARK: - 打擊

    func hit(kind: HitKind, at p: CGPoint, now: TimeInterval,
             from: CGPoint? = nil, direction: Int = 1) {
        guard phase != .finished else { return }
        wake(now)
        if taps == 0 {
            startTime = now
            emit(.runStarted)
        }
        phase = .fighting
        taps += 1
        endTime = now
        lastActivity = now

        if let last = lastHit, now - last < GameConfig.comboWindow { combo += 1 } else { combo = 1 }
        lastHit = now

        if mode == .mokugyo {
            merit += 1
            maxCombo = max(maxCombo, combo)
            emit(.hit(HitEvent(kind: .tap, location: p, from: p, direction: 1, damage: 0, combo: combo,
                               multiplier: 1, crit: false, blocked: false, power: GameConfig.mokugyoPower)))
            return
        }

        var base: Double
        var power: Double
        switch kind {
        case .tap: base = GameConfig.tapDamage; power = GameConfig.tapPower
        case .swipe: base = GameConfig.swipeDamage; power = GameConfig.swipePower
        case .charge: base = GameConfig.chargeDamage; power = GameConfig.chargePower
        }

        var crit = false
        if kind == .tap, let w = weakSpot, now < w.until,
           hypot(Double(p.x - w.center.x), Double(p.y - w.center.y)) < w.radius {
            crit = true
            base = GameConfig.critDamage
            power = GameConfig.critPower
            combo += GameConfig.critComboBonus - 1
            hideWeakSpot(hit: true)
        }
        maxCombo = max(maxCombo, combo)
        if combo > bestCombo { bestCombo = combo; recordCombo = true }

        var blocked = false
        if enemy.hasArmor {
            if kind == .tap && !crit {
                blocked = true
                base *= GameConfig.armorDamageFactor
            } else {
                enemy.hasArmor = false
                emit(.armorOff(at: p))
            }
        }

        let multiplier = GameConfig.multiplier(forCombo: combo)
        let damage = base * multiplier
        enemy.hp = max(0, enemy.hp - damage)
        emit(.hit(HitEvent(kind: kind, location: p, from: from ?? p, direction: direction, damage: damage,
                           combo: combo, multiplier: multiplier, crit: crit, blocked: blocked, power: power)))

        let step = GameConfig.milestoneInterval
        let inc = crit ? GameConfig.critComboBonus : 1
        if combo >= step && combo / step > (combo - inc) / step {
            emit(.comboMilestone(combo / step * step))
        }

        if enemy.hp <= 0 {
            knockOut(now: now)
        } else if kind == .tap && !crit && weakSpot == nil
                    && taps > GameConfig.weakSpotMinTaps && random() < GameConfig.weakSpotChance {
            showWeakSpot(now: now)
        }
    }

    // MARK: - 擊退

    private func knockOut(now: TimeInterval) {
        let wasBoss = enemy.kind == .boss
        let wasNew = enemy.isNewCharacter
        let defeated = enemy.characterIndex
        run += 1
        if run > bestRun { bestRun = run; recordRun = true }
        if wasNew {
            unlockedCount = min(unlockedCount + 1, GameConfig.totalCharacters)
            newlyUnlocked.append(defeated)
            emit(.characterUnlocked(total: unlockedCount))
        }
        emit(.ko(KOEvent(boss: wasBoss, run: run, newCharacter: wasNew, characterIndex: defeated)))

        if GameConfig.enemyKind(forRun: run) == .boss && unlockedCount < GameConfig.totalCharacters {
            characterIndex = unlockedCount
            nextIsNew = true
        } else {
            nextIsNew = false
            if unlockedCount > 1 {
                let candidates = (0..<unlockedCount).filter { $0 != characterIndex }
                let i = min(Int(random() * Double(candidates.count)), candidates.count - 1)
                characterIndex = candidates[max(i, 0)]
            }
        }
        // 擊退後連擊計時延後，避免換人時斷連擊
        lastHit = now + GameConfig.koGrace
        spawn(dropped: true)
    }

    // MARK: - 弱點

    func showWeakSpot(now: TimeInterval) {
        if let area = weakSpotArea {
            let x = Double(area.minX) + random() * Double(area.width)
            let y = Double(area.minY) + random() * Double(area.height)
            showWeakSpot(center: CGPoint(x: x, y: y), now: now)
            return
        }
        let w = Double(stage.width), h = Double(stage.height)
        let x = w * (GameConfig.weakSpotX.min + random() * GameConfig.weakSpotX.span)
        let y = h * (GameConfig.weakSpotY.min + random() * GameConfig.weakSpotY.span)
        showWeakSpot(center: CGPoint(x: x, y: y), now: now)
    }

    func showWeakSpot(center: CGPoint, now: TimeInterval) {
        let spot = WeakSpot(center: center,
                            radius: weakSpotRadius ?? Double(stage.width) * GameConfig.weakSpotRadiusFraction,
                            until: now + GameConfig.weakSpotLife)
        weakSpot = spot
        emit(.weakSpotShown(spot))
    }

    private func hideWeakSpot(hit: Bool) {
        guard weakSpot != nil else { return }
        weakSpot = nil
        emit(.weakSpotHidden(hit: hit))
    }

    // MARK: - 時間推進（呼叫端約每 50ms 呼叫一次）

    func tick(now: TimeInterval) {
        if let w = weakSpot, now >= w.until { hideWeakSpot(hit: false) }

        if isPressing {
            if mode == .rage, !pressMoved, !isCharging, now - pressStart >= GameConfig.chargeStartDelay {
                isCharging = true
                if !holdKeepsCombo { combo = 0 }
                emit(.chargingStarted)
            }
            return   // 按住時不進冷卻
        }
        switch phase {
        case .fighting:
            if now - lastActivity >= GameConfig.idleToCooling {
                phase = .cooling
                coolingStart = now
                emit(.coolingStarted)
            }
        case .cooling:
            if now - coolingStart >= GameConfig.coolingDuration { finish() }
        case .idle, .finished:
            break
        }
    }

    private func wake(_ now: TimeInterval) {
        if phase == .cooling {
            phase = .fighting
            emit(.coolingCancelled)
        }
    }

    private func finish() {
        guard phase != .finished, taps > 0 else { return }
        phase = .finished
        hideWeakSpot(hit: false)
        let summary = RunSummary(
            mode: mode, koCount: run, taps: taps, maxCombo: maxCombo,
            seconds: max(1, Int((endTime - startTime).rounded())), merit: merit,
            newBestCombo: (recordCombo && bestCombo >= 10) ? bestCombo : nil,
            newBestRun: recordRun ? bestRun : nil,
            unlockedCharacters: newlyUnlocked)
        recordCombo = false
        recordRun = false
        emit(.finished(summary))
    }

    private func emit(_ e: GameEvent) { onEvent?(e) }
}
