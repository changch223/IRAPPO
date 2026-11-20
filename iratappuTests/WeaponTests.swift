import Testing
import Foundation
import CoreGraphics
@testable import IRAPPO

struct WeaponTests {
    private func makeProgress() -> (WeaponProgress, UserDefaults) {
        let d = UserDefaults(suiteName: "weapon-test-\(UUID().uuidString)")!
        return (WeaponProgress(defaults: d), d)
    }

    private func hitEvent(_ kind: HitKind, crit: Bool = false) -> GameEvent {
        .hit(HitEvent(kind: kind, location: .zero, from: .zero, direction: 1, damage: 2, combo: 1,
                      multiplier: 1, crit: crit, blocked: false, power: 1))
    }

    // MARK: 武器表

    @Test func sixWeaponsMatchSpecTable() {
        #expect(Weapons.all.map(\.id) == [.fist, .slipper, .hammer, .bolt, .kb, .bubble])
        #expect(Weapons.all.map(\.emoji) == ["👊", "🩴", "🔨", "⚡", "⌨️", "🫧"])
        #expect(Weapons.all.map { $0.unlock?.stat } == [nil, .swipes, .kos, .charges, .crits, .taps])
        #expect(Weapons.weapon(.hammer).koEffect == .shatter)
        #expect(Weapons.weapon(.hammer).sound.ko == "shatter")
        #expect(Weapons.weapon(.bubble).hitEffect == .bubbles)
        #expect(Weapons.weapon(.bolt).haptic == .rumble)
        #expect(Weapons.weapon(.hammer).haptic == .sharp)
        #expect(Weapons.weapon(.bubble).haptic == .soft)
    }

    @Test func weaponHasNoCombatValues() {
        // 規格 5.1：Weapon 不准放任何戰鬥數值。欄位若被加了數值（傷害、連擊時間…）這個測試會失敗。
        let labels = Set(Mirror(reflecting: Weapons.all[0]).children.compactMap(\.label))
        #expect(labels == ["id", "emoji", "nameKey", "descKey", "hitEffect", "koEffect", "sound", "haptic", "shakesScreen", "unlock"])
        let soundLabels = Set(Mirror(reflecting: Weapons.all[0].sound).children.compactMap(\.label))
        #expect(soundLabels == ["hit", "ko", "pitchesWithCombo"])
    }

    @Test func engineDoesNotKnowAboutWeapons() {
        let e = GameEngine()
        for child in Mirror(reflecting: e).children {
            #expect(!(child.value is Weapon))
            #expect(!(child.value is WeaponID))
            #expect(!(child.value is WeaponProgress))
        }
    }

    /// 同樣的操作序列，不論選哪把武器，引擎輸出完全一樣
    @Test func engineOutputIdenticalForEveryWeapon() {
        func run() -> [GameEvent] {
            let e = GameEngine(unlockedCount: 3, stage: CGSize(width: 400, height: 600), random: { 0.5 })
            var events: [GameEvent] = []
            e.onEvent = { events.append($0) }
            e.reset(mode: .rage)
            var t = 0.0
            for i in 0..<40 {
                e.hit(kind: i % 7 == 0 ? .swipe : .tap, at: CGPoint(x: 100 + Double(i), y: 300), now: t)
                t += 0.1
            }
            e.pressBegan(at: CGPoint(x: 50, y: 50), now: t)
            e.tick(now: t + 0.3)
            if case .charge(let hits, let origin) = e.pressEnded(at: CGPoint(x: 50, y: 50), now: t + 1.5) {
                for i in 0..<hits { e.chargeHit(origin: origin, now: t + 1.5 + Double(i) * 0.09) }
            }
            e.tick(now: t + 5)
            e.tick(now: t + 9)
            return events
        }
        let baseline = run()
        for w in Weapons.all {
            _ = w   // 選哪把武器都不會傳進引擎
            #expect(run() == baseline)
        }
    }

    // MARK: 解鎖門檻

    @Test func thresholdsMatchSpec() {
        #expect(GameConfig.unlockThreshold(for: .slipper) == 30)
        #expect(GameConfig.unlockThreshold(for: .hammer) == 50)
        #expect(GameConfig.unlockThreshold(for: .bolt) == 20)
        #expect(GameConfig.unlockThreshold(for: .kb) == 20)
        #expect(GameConfig.unlockThreshold(for: .bubble) == 2000)
        #if DEBUG
        #expect(GameConfig.useDebugThresholds == false)   // 原型門檻預設關閉
        #endif
    }

    @Test func fistUnlockedFromStart() {
        let (p, _) = makeProgress()
        #expect(p.isUnlocked(.fist))
        #expect(!p.isUnlocked(.slipper))
    }

    @Test func slipperUnlocksAt30SwipesExactlyOnce() {
        let (p, _) = makeProgress()
        for _ in 0..<29 { #expect(p.record(.swipes).isEmpty) }
        #expect(!p.isUnlocked(.slipper))
        let gained = p.record(.swipes)
        #expect(gained.map(\.id) == [.slipper])
        #expect(p.isUnlocked(.slipper))
        #expect(p.record(.swipes).isEmpty)               // 不重複
    }

    @Test func eachWeaponUnlocksFromItsOwnStatOnly() {
        let (p, _) = makeProgress()
        #expect(p.record(.kos, by: 49).isEmpty)
        #expect(p.record(.kos).map(\.id) == [.hammer])
        #expect(p.record(.charges, by: 20).map(\.id) == [.bolt])
        #expect(p.record(.crits, by: 20).map(\.id) == [.kb])
        #expect(p.record(.taps, by: 1999).isEmpty)
        #expect(p.record(.taps).map(\.id) == [.bubble])
        #expect(!p.isUnlocked(.slipper))
    }

    @Test func progressIsClampedToRequirement() {
        let (p, _) = makeProgress()
        p.record(.swipes, by: 12)
        let w = Weapons.weapon(.slipper)
        #expect(p.progress(for: w).current == 12)
        #expect(p.progress(for: w).required == 30)
        p.record(.swipes, by: 100)
        #expect(p.progress(for: w).current == 30)
    }

    @Test func progressPersistsAcrossInstances() {
        let (p, d) = makeProgress()
        p.record(.swipes, by: 7)
        p.record(.kos, by: 50)                           // 解鎖時會立即寫入
        p.flush()
        let p2 = WeaponProgress(defaults: d)
        #expect(p2.count(.swipes) == 7)
        #expect(p2.isUnlocked(.hammer))
        #expect(!p2.isUnlocked(.slipper))
    }

    // MARK: 事件 → 統計

    @Test func incrementsOnlyInRageMode() {
        #expect(WeaponProgress.increments(for: hitEvent(.tap), mode: .mokugyo).isEmpty)
        #expect(WeaponProgress.increments(for: .ko(KOEvent(boss: false, run: 1, newCharacter: false, characterIndex: 0)),
                                          mode: .mokugyo).isEmpty)
    }

    @Test func incrementsMapping() {
        #expect(WeaponProgress.increments(for: hitEvent(.tap), mode: .rage) == [.taps])
        #expect(WeaponProgress.increments(for: hitEvent(.swipe), mode: .rage) == [.taps, .swipes])
        #expect(WeaponProgress.increments(for: hitEvent(.tap, crit: true), mode: .rage) == [.taps, .crits])
        #expect(WeaponProgress.increments(for: hitEvent(.charge), mode: .rage) == [.taps])     // 爆發每一下只算打擊
        #expect(WeaponProgress.increments(for: .chargeReleased(hits: 3), mode: .rage) == [.charges])
        #expect(WeaponProgress.increments(for: .ko(KOEvent(boss: true, run: 4, newCharacter: true, characterIndex: 3)),
                                          mode: .rage) == [.kos])
        #expect(WeaponProgress.increments(for: .coolingStarted, mode: .rage).isEmpty)
    }

    @Test func engineEmitsChargeReleasedOnce() {
        let e = GameEngine(unlockedCount: 3, stage: CGSize(width: 400, height: 600), random: { 0.99 })
        var events: [GameEvent] = []
        e.onEvent = { events.append($0) }
        e.reset(mode: .rage)
        e.pressBegan(at: .zero, now: 0)
        e.tick(now: 0.3)
        _ = e.pressEnded(at: .zero, now: 2.1)
        let released = events.filter { if case .chargeReleased = $0 { return true } else { return false } }
        #expect(released == [.chargeReleased(hits: 3)])
    }

    // MARK: 晃畫面旗標

    @Test func onlyBubbleDoesNotShakeScreen() {
        #expect(Weapons.all.filter { !$0.shakesScreen }.map(\.id) == [.bubble])
    }

    @Test func bubbleHitNeverShakesButKeycapsDo() {
        let fx = FXModel()
        let decals = DecalModel()
        let wfx = WeaponFX(fx: fx, decals: decals)
        wfx.stage = CGSize(width: 400, height: 600)
        for _ in 0..<20 { wfx.hit(Weapons.weapon(.bubble), at: CGPoint(x: 100, y: 100), power: 2) }
        #expect(fx.shakeOffset() == .zero)

        for _ in 0..<5 { wfx.hit(Weapons.weapon(.kb), at: CGPoint(x: 100, y: 100), power: 1) }
        let moved = (0..<10).contains { _ in fx.shakeOffset() != .zero }
        #expect(moved)
    }

    @Test func reduceMotionSuppressesShakeAndFlash() {
        let fx = FXModel()
        let wfx = WeaponFX(fx: fx, decals: DecalModel())
        wfx.stage = CGSize(width: 400, height: 600)
        wfx.reduceMotion = true
        var flashed = false
        wfx.flash = { _ in flashed = true }
        wfx.hit(Weapons.weapon(.bolt), at: CGPoint(x: 100, y: 100), power: 2)
        #expect(fx.shakeOffset() == .zero)
        #expect(!flashed)
    }

    @Test func flashIsCapped() {
        let wfx = WeaponFX(fx: FXModel(), decals: DecalModel())
        wfx.stage = CGSize(width: 400, height: 600)
        var values: [Double] = []
        wfx.flash = { values.append($0) }
        wfx.hit(Weapons.weapon(.bolt), at: CGPoint(x: 100, y: 100), power: 2)
        #expect(values == [WeaponFXConfig.hitFlash])
        #expect(values.allSatisfy { $0 <= 0.5 })
        #expect(WeaponFXConfig.koFlash <= 0.6)
    }

    @Test func flashIsThrottledTo333ms() {
        let wfx = WeaponFX(fx: FXModel(), decals: DecalModel())
        wfx.stage = CGSize(width: 400, height: 600)
        var clock = 100.0
        wfx.now = { clock }
        var count = 0
        wfx.flash = { _ in count += 1 }
        let bolt = Weapons.weapon(.bolt)
        wfx.hit(bolt, at: CGPoint(x: 10, y: 10), power: 1)       // 閃
        clock += 0.1
        wfx.hit(bolt, at: CGPoint(x: 10, y: 10), power: 1)       // 略過
        clock += 0.2
        wfx.hit(bolt, at: CGPoint(x: 10, y: 10), power: 1)       // 距第一次 0.3 秒，仍略過
        #expect(count == 1)
        clock += 0.1
        wfx.hit(bolt, at: CGPoint(x: 10, y: 10), power: 1)       // 0.4 秒後可以再閃
        #expect(count == 2)
        #expect(wfx.decals.decals.count == 4)                    // 焦痕每一下都留
    }
}
