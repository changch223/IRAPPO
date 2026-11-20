import Testing
import CoreGraphics
@testable import IRAPPO

/// 階段 2 驗收：GameEngine 規則。時間全部由測試傳入。
struct GameEngineTests {
    private let stage = CGSize(width: 400, height: 600)
    private let p = CGPoint(x: 200, y: 300)

    /// random 固定回傳 0.99：不會出現弱點（機率 0.1），隨機角色取最後一個候選。
    private func makeEngine(unlocked: Int = 3, random: Double = 0.99) -> (GameEngine, EventLog) {
        let e = GameEngine(unlockedCount: unlocked, stage: stage, random: { random })
        let log = EventLog()
        e.onEvent = { log.events.append($0) }
        e.reset(mode: .rage)
        log.events.removeAll()
        return (e, log)
    }

    final class EventLog {
        var events: [GameEvent] = []
        var hits: [HitEvent] { events.compactMap { if case .hit(let h) = $0 { return h } else { return nil } } }
        var kos: [KOEvent] { events.compactMap { if case .ko(let k) = $0 { return k } else { return nil } } }
        var spawned: [Enemy] { events.compactMap { if case .enemySpawned(let e, _) = $0 { return e } else { return nil } } }
        func contains(_ ev: GameEvent) -> Bool { events.contains(ev) }
    }

    /// 打 n 下點擊，間隔 0.1 秒，回傳最後時間
    @discardableResult
    private func tapMany(_ e: GameEngine, _ n: Int, from t: Double = 0, step: Double = 0.1) -> Double {
        var now = t
        for _ in 0..<n { e.hit(kind: .tap, at: p, now: now); now += step }
        return now - step
    }

    // MARK: 血量與對手循環

    @Test func hpFormula() {
        #expect(GameConfig.hp(forRun: 0, kind: .normal) == 60)
        #expect(GameConfig.hp(forRun: 1, kind: .normal) == 90)
        #expect(GameConfig.hp(forRun: 7, kind: .normal) == 270)
        #expect(GameConfig.hp(forRun: 8, kind: .normal) == 300)
        #expect(GameConfig.hp(forRun: 100, kind: .normal) == 300)
        #expect(GameConfig.hp(forRun: 3, kind: .boss) == 300)   // (60+90)=150 ×2
        #expect(GameConfig.hp(forRun: 20, kind: .boss) == 600)
    }

    @Test func enemyCycle() {
        let kinds = (0..<8).map { GameConfig.enemyKind(forRun: $0) }
        #expect(kinds == [.normal, .armor, .normal, .boss, .normal, .armor, .normal, .boss])
    }

    @Test func enemiesSpawnInCycleOrderWithHP() {
        let (e, log) = makeEngine()
        var t = 0.0
        for _ in 0..<4 {
            // 用蓄力爆發的傷害快速打倒（每下 6）；直接重複打直到擊退
            let before = e.run
            while e.run == before { e.hit(kind: .charge, at: p, now: t); t += 0.05 }
        }
        let kinds = log.spawned.map(\.kind)
        #expect(kinds == [.armor, .normal, .boss, .normal])
        #expect(log.spawned.map(\.maxHP) == [90, 120, 300, 180])
        #expect(log.spawned[2].hasArmor == false)
        #expect(log.spawned[0].hasArmor == true)
    }

    // MARK: 連擊

    @Test func comboWindowAndReset() {
        let (e, _) = makeEngine()
        e.hit(kind: .tap, at: p, now: 10.0)
        e.hit(kind: .tap, at: p, now: 10.5)
        #expect(e.combo == 2)
        e.hit(kind: .tap, at: p, now: 11.2)   // 間隔 0.7 > 0.6
        #expect(e.combo == 1)
    }

    @Test func comboMultipliers() {
        #expect(GameConfig.multiplier(forCombo: 1) == 1)
        #expect(GameConfig.multiplier(forCombo: 9) == 1)
        #expect(GameConfig.multiplier(forCombo: 10) == 1.5)
        #expect(GameConfig.multiplier(forCombo: 29) == 1.5)
        #expect(GameConfig.multiplier(forCombo: 30) == 2)
        #expect(GameConfig.multiplier(forCombo: 59) == 2)
        #expect(GameConfig.multiplier(forCombo: 60) == 3)
    }

    @Test func multiplierAppliesToDamage() {
        let (e, log) = makeEngine()
        tapMany(e, 10)
        let hits = log.hits
        #expect(hits[8].damage == 2)
        #expect(hits[9].multiplier == 1.5)
        #expect(hits[9].damage == 3)
    }

    @Test func rageLevels() {
        #expect(GameConfig.rageLevel(forCombo: 19) == .calm)
        #expect(GameConfig.rageLevel(forCombo: 20) == .mid)
        #expect(GameConfig.rageLevel(forCombo: 40) == .high)
        #expect(GameConfig.rageLevel(forCombo: 50) == .max)
        #expect(GameConfig.rageLevel(forCombo: 60) == .promax)
    }

    // MARK: 蓄力凍結連擊

    @Test func chargeFreezesComboWhenHeldAliveCombo() {
        let (e, log) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0.0)
        e.hit(kind: .tap, at: p, now: 0.1)
        #expect(e.combo == 2)
        e.pressBegan(at: p, now: 0.2)           // 連擊仍有效
        e.tick(now: 0.45)                        // 超過 220ms → 蓄力中
        #expect(e.isCharging)
        #expect(e.combo == 2)                    // 沒被歸零
        e.tick(now: 1.5)                         // 按住超過連擊判定時間，連擊仍凍結
        #expect(e.combo == 2)
        let r = e.pressEnded(at: p, now: 2.3)    // 按住 2.1 秒 → 3 下
        #expect(r == .charge(hits: 3, origin: p))
        #expect(e.lastHit == 2.3)                // 放開時 lastHit = now
        e.chargeHit(origin: p, now: 2.3)
        e.chargeHit(origin: p, now: 2.39)
        e.chargeHit(origin: p, now: 2.48)
        #expect(e.combo == 5)                    // 接著原本連擊往上加
        #expect(log.hits.suffix(3).allSatisfy { $0.kind == .charge && $0.damage > 0 })
    }

    @Test func chargeStartResetsComboIfAlreadyBroken() {
        let (e, _) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0.0)
        e.hit(kind: .tap, at: p, now: 0.1)
        e.pressBegan(at: p, now: 5.0)            // 開始按時連擊已斷
        e.tick(now: 5.3)
        #expect(e.isCharging)
        #expect(e.combo == 0)
        let r = e.pressEnded(at: p, now: 6.3)
        #expect(r == .charge(hits: 2, origin: p))
        e.chargeHit(origin: p, now: 6.3)
        #expect(e.combo == 1)
    }

    @Test func chargeTiers() {
        #expect(GameConfig.chargeHits(forHold: 0.9) == 0)
        #expect(GameConfig.chargeHits(forHold: 1.0) == 2)
        #expect(GameConfig.chargeHits(forHold: 2.0) == 3)
        #expect(GameConfig.chargeHits(forHold: 3.5) == 5)
    }

    @Test func shortHoldIsTapAndDoesNotCharge() {
        let (e, log) = makeEngine()
        e.pressBegan(at: p, now: 0)
        e.tick(now: 0.3)
        #expect(e.isCharging)
        let r = e.pressEnded(at: p, now: 0.8)    // 蓄力不足 1 秒 → 一下拳
        #expect(r == .tap)
        #expect(log.hits.count == 1)
        #expect(log.hits[0].kind == .tap)
    }

    @Test func movingCancelsCharge() {
        let (e, _) = makeEngine()
        e.pressBegan(at: p, now: 0)
        e.pressMoved(to: CGPoint(x: p.x + 30, y: p.y), now: 0.1)   // 30 > 400*6%
        e.tick(now: 0.5)
        #expect(!e.isCharging)
    }

    // MARK: 滑動

    @Test func swipeClassification() {
        let (e, log) = makeEngine()
        e.pressBegan(at: CGPoint(x: 100, y: 300), now: 0)
        let r = e.pressEnded(at: CGPoint(x: 200, y: 300), now: 0.2)   // 100 > 64, < 450ms
        #expect(r == .swipe)
        #expect(log.hits[0].kind == .swipe)
        #expect(log.hits[0].damage == 5)
        #expect(log.hits[0].direction == 1)

        e.pressBegan(at: CGPoint(x: 100, y: 300), now: 5)
        let slow = e.pressEnded(at: CGPoint(x: 200, y: 300), now: 5.5)   // 太慢 → 點
        #expect(slow == .tap)
    }

    // MARK: 鐵頭

    private func engineAtArmor() -> (GameEngine, EventLog, Double) {
        let (e, log) = makeEngine()
        var t = 0.0
        while e.run < 1 { e.hit(kind: .charge, at: p, now: t); t += 0.05 }
        #expect(e.enemy.kind == .armor)
        return (e, log, t + 5)   // 之後的測試從連擊斷掉的時間開始
    }

    @Test func armorBlocksTapWith40PercentDamage() {
        let (e, log, t) = engineAtArmor()
        let hp0 = e.enemy.hp
        e.hit(kind: .tap, at: p, now: t)
        let h = log.hits.last!
        #expect(h.blocked)
        #expect(h.damage == 2 * 0.4)
        #expect(e.enemy.hp == hp0 - 0.8)
        #expect(e.enemy.hasArmor)
    }

    @Test func armorRemovedBySwipe() {
        let (e, log, t) = engineAtArmor()
        e.hit(kind: .swipe, at: p, now: t)
        #expect(!e.enemy.hasArmor)
        #expect(log.events.contains { if case .armorOff = $0 { return true } else { return false } })
        e.hit(kind: .tap, at: p, now: t + 2)
        #expect(log.hits.last!.blocked == false)
        #expect(log.hits.last!.damage == 2)
    }

    @Test func armorRemovedByCharge() {
        let (e, _, t) = engineAtArmor()
        e.hit(kind: .charge, at: p, now: t)
        #expect(!e.enemy.hasArmor)
    }

    @Test func armorRemovedByCrit() {
        let (e, log, t) = engineAtArmor()
        e.showWeakSpot(center: p, now: t)
        e.hit(kind: .tap, at: p, now: t + 0.1)
        #expect(log.hits.last!.crit)
        #expect(!log.hits.last!.blocked)
        #expect(!e.enemy.hasArmor)
    }

    // MARK: 爆擊

    @Test func critAddsThreeComboAndTenDamage() {
        let (e, log) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)                   // combo 1
        e.showWeakSpot(center: CGPoint(x: 50, y: 50), now: 0.1)
        e.hit(kind: .tap, at: CGPoint(x: 60, y: 60), now: 0.2)
        #expect(e.combo == 4)                              // 1 + 3
        #expect(log.hits.last!.crit)
        #expect(log.hits.last!.damage == 10)
        #expect(e.weakSpot == nil)
    }

    @Test func weakSpotMissAndExpiry() {
        let (e, log) = makeEngine()
        e.showWeakSpot(center: CGPoint(x: 50, y: 50), now: 0)
        e.hit(kind: .tap, at: CGPoint(x: 300, y: 300), now: 0.1)   // 沒點中
        #expect(log.hits.last!.crit == false)
        #expect(e.weakSpot != nil)
        e.tick(now: 1.8)                                           // > 1.7 秒
        #expect(e.weakSpot == nil)
        #expect(log.contains(.weakSpotHidden(hit: false)))
    }

    @Test func swipeCannotCrit() {
        let (e, log) = makeEngine()
        e.showWeakSpot(center: p, now: 0)
        e.hit(kind: .swipe, at: p, now: 0.1)
        #expect(log.hits.last!.crit == false)
    }

    // MARK: 擊退緩衝

    @Test func koGraceKeepsComboAcrossEnemies() {
        let (e, log) = makeEngine()
        var t = 0.0
        var tKO = 0.0
        while log.kos.isEmpty { tKO = t; e.hit(kind: .charge, at: p, now: t); t += 0.1 }
        let comboAtKO = e.combo
        #expect(e.lastHit == tKO + 0.35)                 // last = now + 350ms
        // 擊退後 0.9 秒才打（距離擊退那一下 > 0.6，但有 0.35 緩衝）
        e.hit(kind: .tap, at: p, now: tKO + 0.9)
        #expect(e.combo == comboAtKO + 1)
        #expect(log.kos[0].boss == false)
    }

    @Test func comboBreaksWithoutGrace() {
        let (e, _) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        e.hit(kind: .tap, at: p, now: 0.9)
        #expect(e.combo == 1)
    }

    // MARK: 冷卻

    @Test func idleLeadsToCoolingThenFinished() {
        let (e, log) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        e.tick(now: 0.9)
        #expect(e.phase == .fighting)
        e.tick(now: 1.0)
        #expect(e.phase == .cooling)
        #expect(log.contains(.coolingStarted))
        e.tick(now: 2.9)
        #expect(e.phase == .cooling)
        e.tick(now: 3.0)
        #expect(e.phase == .finished)
        let summary = log.events.compactMap { ev -> RunSummary? in if case .finished(let s) = ev { return s } else { return nil } }.first
        #expect(summary?.taps == 1)
        #expect(summary?.koCount == 0)
        #expect(summary?.seconds == 1)
    }

    @Test func hitCancelsCooling() {
        let (e, log) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        e.tick(now: 1.0)
        #expect(e.phase == .cooling)
        e.hit(kind: .tap, at: p, now: 1.5)
        #expect(e.phase == .fighting)
        #expect(log.contains(.coolingCancelled))
        e.tick(now: 2.4)                               // 距離新一下不到 1 秒
        #expect(e.phase == .fighting)
    }

    @Test func pressingBlocksCooling() {
        let (e, _) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        e.pressBegan(at: p, now: 0.5)
        e.tick(now: 3.0)
        #expect(e.phase == .fighting)
    }

    @Test func noFinishWithoutTaps() {
        let (e, _) = makeEngine()
        e.tick(now: 100)
        #expect(e.phase == .idle)
    }

    // MARK: 沒有上限、新角色、紀錄

    @Test func runHasNoUpperLimit() {
        let (e, log) = makeEngine(unlocked: GameConfig.totalCharacters)
        var t = 0.0
        while e.run < 60 { e.hit(kind: .charge, at: p, now: t); t += 0.05 }
        #expect(e.phase == .fighting)
        #expect(log.kos.count == 60)
        #expect(e.enemy.maxHP == (e.enemy.kind == .boss ? 600 : 300))
    }

    @Test func bossIsNextLockedCharacterAndKOUnlocksIt() {
        let (e, log) = makeEngine(unlocked: 3)
        var t = 0.0
        while e.run < 3 { e.hit(kind: .charge, at: p, now: t); t += 0.05 }
        #expect(e.enemy.kind == .boss)
        #expect(e.enemy.isNewCharacter)
        #expect(e.enemy.characterIndex == 3)
        while e.run < 4 { e.hit(kind: .charge, at: p, now: t); t += 0.05 }
        #expect(e.unlockedCount == 4)
        #expect(log.kos.last!.newCharacter)
        #expect(log.events.contains(.characterUnlocked(total: 4)))
    }

    @Test func randomCharacterNeverRepeatsPrevious() {
        let (e, log) = makeEngine(unlocked: 3, random: 0)
        var t = 0.0
        var prev = e.enemy.characterIndex
        for _ in 0..<2 {
            let r = e.run
            while e.run == r { e.hit(kind: .charge, at: p, now: t); t += 0.05 }
            #expect(e.enemy.characterIndex != prev)
            prev = e.enemy.characterIndex
        }
        #expect(!log.kos.isEmpty)
    }

    @Test func newBestRecordsInSummary() {
        let (e, log) = makeEngine()
        tapMany(e, 12)
        e.tick(now: 2.5)
        e.tick(now: 5.0)
        let s = log.events.compactMap { ev -> RunSummary? in if case .finished(let s) = ev { return s } else { return nil } }.first
        #expect(s?.newBestCombo == 12)
        #expect(s?.maxCombo == 12)
        #expect(s?.newBestRun == nil)
    }

    @Test func mokugyoCountsMeritWithoutEnemyDamage() {
        let e = GameEngine(unlockedCount: 3, stage: stage, random: { 0.99 })
        e.reset(mode: .mokugyo)
        let hp = e.enemy.hp
        for i in 0..<5 { e.hit(kind: .tap, at: p, now: Double(i) * 0.1) }
        #expect(e.merit == 5)
        #expect(e.enemy.hp == hp)
        let r = e.pressEnded(at: p, now: 1)    // 沒有按下 → ignored
        #expect(r == .ignored)
    }

    @Test func mokugyoNeverSwipesOrCharges() {
        let e = GameEngine(unlockedCount: 3, stage: stage, random: { 0.99 })
        e.reset(mode: .mokugyo)
        e.pressBegan(at: CGPoint(x: 100, y: 300), now: 0)
        e.tick(now: 0.5)
        #expect(!e.isCharging)
        let r = e.pressEnded(at: CGPoint(x: 300, y: 300), now: 0.6)
        #expect(r == .tap)
    }

    // MARK: 追加：連擊里程碑、弱點出現規則、取消、重複結算、慢拖

    private func milestones(_ log: EventLog) -> [Int] {
        log.events.compactMap { if case .comboMilestone(let n) = $0 { return n } else { return nil } }
    }

    @Test func milestoneAt50() {
        let (e, log) = makeEngine()
        tapMany(e, 50)
        #expect(e.combo == 50)
        #expect(milestones(log) == [50])
    }

    @Test func milestoneWhenCritJumps48To51() {
        let (e, log) = makeEngine()
        let t = tapMany(e, 48)
        #expect(e.combo == 48)
        #expect(milestones(log).isEmpty)
        e.showWeakSpot(center: p, now: t)
        e.hit(kind: .tap, at: p, now: t + 0.1)
        #expect(e.combo == 51)
        #expect(milestones(log) == [50])
        e.hit(kind: .tap, at: p, now: t + 0.2)
        #expect(milestones(log) == [50])   // 不重複
    }

    @Test func weakSpotAppearsOnlyAfterSixTaps() {
        let (e, log) = makeEngine(random: 0.05)   // < 10% → 會出現
        for i in 0..<6 { e.hit(kind: .tap, at: p, now: Double(i) * 0.7) }
        #expect(e.weakSpot == nil)
        e.hit(kind: .tap, at: p, now: 6 * 0.7)     // 第 7 下（已打超過 6 下）
        #expect(e.weakSpot != nil)
        #expect(log.events.contains { if case .weakSpotShown = $0 { return true } else { return false } })
    }

    @Test func weakSpotNotWhenRandomAboveChance() {
        let (e, _) = makeEngine(random: 0.5)
        for i in 0..<20 { e.hit(kind: .tap, at: p, now: Double(i) * 0.7) }
        #expect(e.weakSpot == nil)
    }

    @Test func weakSpotDoesNotReappearOnCrit() {
        let (e, _) = makeEngine(random: 0.05)
        for i in 0..<7 { e.hit(kind: .tap, at: p, now: Double(i) * 0.7) }
        let spot = e.weakSpot!
        e.hit(kind: .tap, at: spot.center, now: 5.0)    // 爆擊
        #expect(e.weakSpot == nil)                      // 爆擊那一下不會立刻再生出新的
    }

    @Test func weakSpotNotSpawnedOnKOHitAndClearedByKO() {
        let (e, log) = makeEngine(random: 0.05)
        var t = 0.0
        // 間隔 0.7 秒：連擊每次歸 1、傷害 2，先打到只剩 2 點血
        while e.enemy.hp > 2 { e.hit(kind: .tap, at: p, now: t); t += 0.7 }
        #expect(e.run == 0)
        e.hit(kind: .tap, at: p, now: t)                // 擊退這一下
        #expect(e.run == 1)
        #expect(log.kos.count == 1)
        #expect(e.weakSpot == nil)
    }

    @Test func pressBeganCancelsCooling() {
        let (e, log) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        e.tick(now: 1.0)
        #expect(e.phase == .cooling)
        e.pressBegan(at: p, now: 1.2)
        #expect(e.phase == .fighting)
        #expect(log.contains(.coolingCancelled))
    }

    @Test func doubleFinishIgnored() {
        let (e, log) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        e.tick(now: 1.0)
        e.tick(now: 3.0)
        e.tick(now: 10.0)
        e.tick(now: 20.0)
        let finished = log.events.filter { if case .finished = $0 { return true } else { return false } }
        #expect(finished.count == 1)
        e.hit(kind: .tap, at: p, now: 21)              // 結算後再打不計
        #expect(e.taps == 1)
    }

    @Test func slowDragBeyondMoveThresholdIsTap() {
        let (e, log) = makeEngine()
        e.pressBegan(at: CGPoint(x: 100, y: 300), now: 0)
        e.pressMoved(to: CGPoint(x: 140, y: 300), now: 0.1)     // 40 > 400*6%
        e.tick(now: 0.5)
        #expect(!e.isCharging)
        let r = e.pressEnded(at: CGPoint(x: 160, y: 300), now: 1.5)   // 60 < 64，且太慢
        #expect(r == .tap)
        #expect(log.hits.last?.kind == .tap)
        #expect(log.hits.last?.location == CGPoint(x: 100, y: 300))
    }

    // MARK: 觸控取消

    @Test func pressCancelledClearsChargingWithoutHit() {
        let (e, log) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        let hitsBefore = log.hits.count
        e.pressBegan(at: p, now: 0.2)
        e.tick(now: 0.5)
        #expect(e.isCharging)
        e.pressCancelled(now: 0.6)
        #expect(!e.isPressing)
        #expect(!e.isCharging)
        #expect(log.contains(.chargingStopped))
        #expect(log.hits.count == hitsBefore)            // 不出手
        #expect(e.pressEnded(at: p, now: 0.7) == .ignored)
    }

    @Test func cooldownWorksAfterCancel() {
        let (e, _) = makeEngine()
        e.hit(kind: .tap, at: p, now: 0)
        e.pressBegan(at: p, now: 0.5)
        e.pressCancelled(now: 0.6)
        e.tick(now: 1.5)                                 // 距離取消 0.9 秒
        #expect(e.phase == .fighting)
        e.tick(now: 1.6)
        #expect(e.phase == .cooling)
    }

    @Test func pressCancelledWhenNotPressingIsNoOp() {
        let (e, log) = makeEngine()
        e.pressCancelled(now: 1)
        #expect(log.events.isEmpty)
    }

    @Test func nextPressAfterCancelUsesFreshOrigin() {
        let (e, log) = makeEngine()
        e.pressBegan(at: CGPoint(x: 10, y: 10), now: 0)
        e.pressCancelled(now: 0.1)
        e.pressBegan(at: CGPoint(x: 300, y: 400), now: 5)
        e.tick(now: 5.1)
        #expect(!e.isCharging)                           // 用新的按下時間，不是舊的 0
        _ = e.pressEnded(at: CGPoint(x: 300, y: 400), now: 5.1)
        #expect(log.hits.last?.location == CGPoint(x: 300, y: 400))
    }
}
