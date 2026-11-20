import Testing
import Foundation
import CoreGraphics
@testable import IRAPPO

struct FlashLimiterTests {
    /// 任一閃光起點之後 1 秒內（含起點）最多 3 次
    private func maxInAnyWindow(_ granted: [TimeInterval]) -> Int {
        granted.map { s in granted.filter { $0 >= s && $0 < s + 1 }.count }.max() ?? 0
    }

    @Test func boltSpamInterleavedWithKnockOutStaysWithinThreePerSecond() {
        var limiter = FlashLimiter()
        var granted: [TimeInterval] = []
        // 雷電每 0.1 秒一下；t=0.2 擊退（武器白閃之後立刻 KO 白閃）
        for i in 0..<40 {
            let t = Double(i) * 0.1
            if limiter.request(now: t, ko: false) { granted.append(t) }
            if i == 2, limiter.request(now: t, ko: true) { granted.append(t) }
        }
        #expect(maxInAnyWindow(granted) <= 3)
        #expect(!granted.isEmpty)
    }

    @Test func consecutiveKnockOutsWithinOneSecondAreCapped() {
        var limiter = FlashLimiter()
        var granted: [TimeInterval] = []
        for t in [0.0, 0.2, 0.4, 0.6, 0.8] {
            if limiter.request(now: t, ko: true) { granted.append(t) }
        }
        #expect(granted == [0.0, 0.2, 0.4])          // 第 4、5 次額度用完，不閃
        let r1 = limiter.request(now: 1.0, ko: true)
        #expect(r1) // 起點 0.0 已滑出視窗，又有額度
    }

    @Test func knockOutMergesWithSimultaneousWeaponFlash() {
        var limiter = FlashLimiter()
        let r2 = limiter.request(now: 5.0, ko: false)
        #expect(r2)
        let r3 = limiter.request(now: 5.02, ko: true)
        #expect(r3)     // 幾乎同時：蓋過武器白閃
        #expect(limiter.starts == [5.0])                  // 算同一次閃光、同一個起點
        let r4 = limiter.request(now: 5.06, ko: true)
        #expect(r4)     // 相差 ≥ 0.05：另算一次
        #expect(limiter.starts.count == 2)
    }

    @Test func knockOutNotNearWeaponFlashCountsAgainstQuota() {
        var limiter = FlashLimiter()
        let r5 = limiter.request(now: 0.0, ko: false)
        #expect(r5)
        let r6 = limiter.request(now: 0.4, ko: false)
        #expect(r6)
        let r7 = limiter.request(now: 0.8, ko: false)
        #expect(r7)
        let r8 = limiter.request(now: 0.9, ko: true)
        #expect(!r8)     // 3 次額度已滿，KO 也不閃
        let r9 = limiter.request(now: 1.0, ko: true)
        #expect(r9)      // 0.0 滑出視窗
    }

    @Test func reduceMotionNeverFlashes() {
        let wfx = WeaponFX(fx: FXModel(), decals: DecalModel())
        wfx.stage = CGSize(width: 400, height: 600)
        wfx.reduceMotion = true
        var count = 0
        wfx.flash = { _ in count += 1 }
        #expect(!wfx.allowFlash(ko: true))
        #expect(!wfx.allowFlash())
        wfx.hit(Weapons.weapon(.bolt), at: CGPoint(x: 100, y: 100), power: 2)
        wfx.knockOut(Weapons.weapon(.bolt))
        #expect(count == 0)
    }

    @Test func weaponFXSharesTheLimiterWithKnockOutFlash() {
        let wfx = WeaponFX(fx: FXModel(), decals: DecalModel())
        wfx.stage = CGSize(width: 400, height: 600)
        var clock = 10.0
        wfx.now = { clock }
        var count = 0
        wfx.flash = { _ in count += 1 }
        wfx.hit(Weapons.weapon(.bolt), at: CGPoint(x: 10, y: 10), power: 1)   // 武器白閃
        #expect(count == 1)
        clock += 0.01
        #expect(wfx.allowFlash(ko: true))                                      // KO 蓋過，不另佔額度
    }
}
