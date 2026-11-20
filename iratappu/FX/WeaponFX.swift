import SwiftUI

enum WeaponFXConfig {
    /// 白閃上限（光敏考量）
    static let hitFlash = 0.5
    static let koFlash = 0.6
    static let maxFlash = 0.6
    /// 全螢幕白閃最短間隔（光敏：每秒最多 3 次）
    static let minFlashInterval: TimeInterval = 0.333
}

/// 武器特效：把 Weapon 的 hitEffect / koEffect 翻成粒子與殘留痕跡。不含任何戰鬥數值。
final class WeaponFX {
    let fx: FXModel
    let decals: DecalModel
    /// 打擊區大小
    var stage: CGSize = .zero
    /// 角色（臉）的中心；nil＝打擊區 48% 高處（舊版版面）
    var faceCenter: CGPoint?
    var reduceMotion = false
    /// 白閃（0...1），由畫面層顯示並淡出
    var flash: ((Double) -> Void)?
    /// 可注入的時鐘（測試用）
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private var limiter = FlashLimiter()

    init(fx: FXModel, decals: DecalModel) {
        self.fx = fx
        self.decals = decals
    }

    /// 特效散佈範圍用的高度：整個螢幕當打擊區時，不要把範圍拉到比寬度的 1.5 倍還高
    private var refH: CGFloat { min(stage.height, stage.width * 1.5) }

    private func rnd(_ range: CGFloat) -> CGFloat { CGFloat.random(in: -0.5...0.5) * range }

    // MARK: 每一下
    func hit(_ weapon: Weapon, at p: CGPoint, power pw: CGFloat) {
        let allowShake = !reduceMotion && weapon.shakesScreen
        // 武器圖示在落點閃一下
        fx.floatText(at: CGPoint(x: p.x, y: p.y + 14), weapon.emoji, size: 42, vx: 0, vy: 0, friction: 1, life: 0.28)
        switch weapon.hitEffect {
        case .impact:
            fx.impact(at: p, power: pw, allowShake: allowShake)
        case .footprint:
            fx.impact(at: p, power: pw * 0.6, allowShake: allowShake)
            footprint(at: p)
        case .crack:
            fx.impact(at: p, power: pw * 0.8, allowShake: allowShake)
            crack(at: p, power: pw)
        case .lightning:
            bolt(to: p)
            scorch(at: p)
            fx.impact(at: p, power: pw * 0.7, allowShake: allowShake)
            zap(WeaponFXConfig.hitFlash)
        case .keycaps:
            fx.keycaps(at: p, count: 3 + Int((pw * 2).rounded()), size: stage.width * 0.062, floor: stage.height)
            if allowShake { fx.shake(amount: 2 + pw * 3) }
        case .bubbles:
            // 泡泡紙：安靜、畫面不晃
            fx.bubbles(at: p, count: 5 + Int((pw * 3).rounded()), spread: 60)
        }
    }

    // MARK: 擊退
    func knockOut(_ weapon: Weapon) {
        let cx = faceCenter?.x ?? stage.width / 2, cy = faceCenter?.y ?? refH * 0.48
        switch weapon.koEffect {
        case .none:
            break
        case .footprints:
            for _ in 0..<6 {
                footprint(at: CGPoint(x: cx + rnd(stage.width * 0.5), y: cy + rnd(refH * 0.3)))
            }
        case .shatter:
            for _ in 0..<4 {
                crack(at: CGPoint(x: cx + rnd(stage.width * 0.6), y: cy + rnd(refH * 0.4)), power: 1.6)
            }
            fx.shards(around: CGPoint(x: cx, y: cy), count: 46, spreadX: stage.width * 0.5, spreadY: refH * 0.3)
        case .lightning:
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) { [weak self] in
                    guard let self else { return }
                    self.bolt(to: CGPoint(x: cx + self.rnd(self.stage.width * 0.6), y: cy + self.rnd(self.refH * 0.2)))
                    if i == 0 { self.zap(WeaponFXConfig.koFlash) }   // 光敏：只有第一道閃電閃白
                }
            }
        case .keycapRain:
            fx.keycaps(at: CGPoint(x: cx, y: cy), count: 26, size: stage.width * 0.062, floor: stage.height)
        case .bubbleBurst:
            fx.bubbles(at: CGPoint(x: cx, y: cy), count: 34, spread: stage.width * 0.7)
        }
    }

    // MARK: 部件
    private func footprint(at p: CGPoint) {
        decals.add(.footprint(center: p, rotation: Double(rnd(1.4)), a: stage.width * 0.055, b: stage.width * 0.12))
    }

    private func crack(at p: CGPoint, power pw: CGFloat) {
        let n = 5 + Int.random(in: 0...2)
        let u = stage.width / 300
        var lines: [[CGPoint]] = []
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi + rnd(0.7)
            let len = (36 + CGFloat.random(in: 0...70)) * pw * u
            var px = p.x, py = p.y
            var pts = [CGPoint(x: px, y: py)]
            for _ in 1...4 {
                px += cos(a) * len / 4 + rnd(10 * u)
                py += sin(a) * len / 4 + rnd(10 * u)
                pts.append(CGPoint(x: px, y: py))
            }
            lines.append(pts)
        }
        decals.add(.crack(lines: lines))
    }

    private func scorch(at p: CGPoint) {
        decals.add(.scorch(center: p, radius: stage.width * 0.12))
    }

    private func bolt(to p: CGPoint) {
        let startX = p.x + rnd(90)
        var pts = [CGPoint(x: startX, y: 0)]
        let n = 7
        for i in 1..<n {
            let f = CGFloat(i) / CGFloat(n)
            pts.append(CGPoint(x: startX + (p.x - startX) * f + rnd(44), y: p.y * f))
        }
        pts.append(p)
        fx.bolt(points: pts)
    }

    /// 白閃 170ms；減少動態效果時不閃
    private func zap(_ opacity: Double) {
        guard allowFlash() else { return }
        flash?(min(opacity, WeaponFXConfig.maxFlash))
    }

    /// 全螢幕白閃的共用節流（邏輯在 FlashLimiter）：減少動態效果時不閃。
    /// 通過時會記下這次閃光，所以呼叫端只在真的要閃的時候呼叫。
    func allowFlash(ko: Bool = false) -> Bool {
        guard !reduceMotion else { return false }
        return limiter.request(now: now(), ko: ko)
    }
}
