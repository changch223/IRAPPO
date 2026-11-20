import SwiftUI
import Combine

// MARK: - 可調常數
enum FXConfig {
    static let emojis = ["💢", "😠", "😡", "🤬", "😤", "💩", "😱", "🤮"]
    static let sparkBaseCount = 7.0
    static let sparkCountPerPower = 5.0
    static let ringLife = 0.28
    static let ringGrowPerPower: CGFloat = 46
    static let textLife = 0.85
    static let textSize: CGFloat = 50
    static let textVY: CGFloat = -2.2
    static let textFriction: CGFloat = 0.94
    static let keycapLetters = Array("QWERTYASDFGZXCVB")
    static let koShake: CGFloat = 20
    static let bossKoShake: CGFloat = 30
    static let shakeBase: CGFloat = 3
    static let shakePerPower: CGFloat = 5
    static let shakeDecayPerFrame: CGFloat = 0.85   // 以 60fps 為單位
    static let shakeCutoff: CGFloat = 0.4
    static let maxParticles = 400
    static let maxStep = 1.0 / 20                   // 單次模擬最大時間步，避免卡頓後瞬移
    static let inkColor = Color(red: 0x1C / 255, green: 0x10 / 255, blue: 0x14 / 255)
    static let sparkColors: [Color] = [.white, Color(red: 1, green: 0xD4 / 255, blue: 0x3B / 255), inkColor]
}

// MARK: - 粒子
struct FXParticle {
    enum Kind { case spark, ring, text, line, keycap, bubble, bolt }
    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var gravity: CGFloat = 0
    var friction: CGFloat = 0.94    // 每 1/60 秒的速度保留比例
    var t: Double = 0
    var life: Double
    var size: CGFloat
    var grow: CGFloat = 0
    var x2: CGFloat = 0
    var y2: CGFloat = 0
    var color: Color = .white
    var outlined = false            // 淺色背景用：加一層深色描邊
    var text: String = ""
    var pts: [CGPoint] = []         // 閃電折線
    var angle: CGFloat = 0          // 鍵帽旋轉
    var va: CGFloat = 0
    var floor: CGFloat = .infinity  // 鍵帽落地線
}

/// 粒子與畫面震動的狀態。只有在有粒子或震動時才 isAnimating（TimelineView 才會跑）。
final class FXModel: ObservableObject {
    @Published private(set) var isAnimating = false
    private(set) var particles: [FXParticle] = []
    private var shake: CGFloat = 0
    private var lastStep: Date?

    /// 一下打擊：火花 + 衝擊環 + 浮字 + 震動。
    func hit(at p: CGPoint, power: CGFloat, text: String? = nil, allowShake: Bool, lightBackground: Bool = false) {
        impact(at: p, power: power, allowShake: allowShake, lightBackground: lightBackground)
        floatText(at: CGPoint(x: p.x + CGFloat.random(in: -24...24), y: p.y - 30),
                  text ?? FXConfig.emojis.randomElement() ?? "💢")
    }

    /// 火花 + 衝擊環 + 震動（不含浮字）。
    func impact(at p: CGPoint, power: CGFloat, allowShake: Bool, lightBackground: Bool = false) {
        let n = Int((FXConfig.sparkBaseCount + Double(power) * FXConfig.sparkCountPerPower).rounded())
        for i in 0..<n {
            let a = Double.random(in: 0..<(2 * .pi))
            let v = CGFloat.random(in: 3...9) * power
            particles.append(FXParticle(
                kind: .spark, x: p.x, y: p.y,
                vx: CGFloat(cos(a)) * v, vy: CGFloat(sin(a)) * v,
                gravity: 0.25, life: Double.random(in: 0.3...0.55),
                size: 3 + power * 1.5, color: FXConfig.sparkColors[i % 3], outlined: true))
        }
        particles.append(FXParticle(
            kind: .ring, x: p.x, y: p.y, life: FXConfig.ringLife,
            size: 6, grow: FXConfig.ringGrowPerPower * power,
            color: lightBackground ? FXConfig.inkColor : .white, outlined: !lightBackground))
        trim()
        if allowShake {
            shake = max(shake, FXConfig.shakeBase + power * FXConfig.shakePerPower)
        }
        wake()
    }

    /// 浮字（預設往上飄、淡出）。也可給初速與重力做成飛出的物件（如頭盔）。
    func floatText(at p: CGPoint, _ text: String, size: CGFloat = FXConfig.textSize,
                   color: Color = FXConfig.inkColor,
                   vx: CGFloat? = nil, vy: CGFloat = FXConfig.textVY, gravity: CGFloat = 0,
                   friction: CGFloat = FXConfig.textFriction, life: Double = FXConfig.textLife,
                   shadowed: Bool = false) {
        particles.append(FXParticle(
            kind: .text, x: p.x, y: p.y,
            vx: vx ?? CGFloat.random(in: -0.7...0.7), vy: vy, gravity: gravity, friction: friction,
            life: life, size: size, color: color, outlined: shadowed, text: text))
        trim()
        wake()
    }

    /// 滑動軌跡
    func trail(from a: CGPoint, to b: CGPoint) {
        particles.append(FXParticle(kind: .line, x: a.x, y: a.y, life: 0.25, size: 16, x2: b.x, y2: b.y,
                                    color: .white, outlined: true))
        trim()
        wake()
    }

    /// 單純畫面震動（擊退用）。
    func shake(amount: CGFloat) {
        shake = max(shake, amount)
        wake()
    }

    /// 鍵帽：噴出、旋轉、受重力落下、碰底反彈
    func keycaps(at p: CGPoint, count: Int, size: CGFloat, floor: CGFloat) {
        for _ in 0..<count {
            particles.append(FXParticle(
                kind: .keycap, x: p.x, y: p.y,
                vx: CGFloat.random(in: -5.5...5.5), vy: CGFloat.random(in: -11 ... -4), gravity: 0.6,
                life: 1.15, size: size,
                text: String(FXConfig.keycapLetters.randomElement() ?? "Q"),
                angle: CGFloat.random(in: -3...3), va: CGFloat.random(in: -0.3...0.3), floor: floor))
        }
        trim()
        wake()
    }

    /// 泡泡：冒出、膨脹、破掉。start 為負表示延遲出現。
    func bubbles(at p: CGPoint, count: Int, spread: CGFloat) {
        for _ in 0..<count {
            particles.append(FXParticle(
                kind: .bubble,
                x: p.x + CGFloat.random(in: -0.5...0.5) * spread, y: p.y + CGFloat.random(in: -0.5...0.5) * spread,
                vx: CGFloat.random(in: -1...1), vy: CGFloat.random(in: -2.8 ... -0.8), t: Double.random(in: -0.15...0),
                life: Double.random(in: 0.35...0.75), size: CGFloat.random(in: 5...18)))
        }
        trim()
        wake()
    }

    /// 白色碎片（鐵鎚擊退）
    func shards(around c: CGPoint, count: Int, spreadX: CGFloat, spreadY: CGFloat) {
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi))
            let v = CGFloat.random(in: 4...17)
            particles.append(FXParticle(
                kind: .spark,
                x: c.x + CGFloat.random(in: -0.5...0.5) * spreadX, y: c.y + CGFloat.random(in: -0.5...0.5) * spreadY,
                vx: CGFloat(cos(a)) * v, vy: CGFloat(sin(a)) * v, gravity: 0.5,
                life: Double.random(in: 0.5...0.9), size: 6, color: .white, outlined: true))
        }
        trim()
        wake()
    }

    /// 閃電（折線）
    func bolt(points: [CGPoint]) {
        guard let first = points.first else { return }
        particles.append(FXParticle(kind: .bolt, x: first.x, y: first.y, life: 0.2, size: 7, pts: points))
        trim()
        wake()
    }

    private func trim() {
        if particles.count > FXConfig.maxParticles {
            particles.removeFirst(particles.count - FXConfig.maxParticles)
        }
    }

    private func wake() {
        if !isAnimating {
            lastStep = nil          // 閒置後第一幀不可帶著過期的時間差
            isAnimating = true
        }
    }

    /// 依時間推進模擬；同一個 date 重複呼叫不會重複推進。
    func step(_ now: Date) {
        guard let last = lastStep else { lastStep = now; return }
        guard now > last else { return }    // 亂序的 date 不可倒轉時鐘
        lastStep = now
        let dt = min(now.timeIntervalSince(last), FXConfig.maxStep)
        let f = CGFloat(dt * 60)

        var i = particles.count - 1
        while i >= 0 {
            particles[i].t += dt
            if particles[i].t >= particles[i].life {
                particles.remove(at: i)
            } else {
                let fr = pow(particles[i].friction, f)
                particles[i].x += particles[i].vx * f
                particles[i].y += particles[i].vy * f
                particles[i].vx *= fr
                particles[i].vy = particles[i].vy * fr + particles[i].gravity * f
                if particles[i].kind == .keycap {
                    particles[i].angle += particles[i].va * f
                    if particles[i].y > particles[i].floor - particles[i].size && particles[i].vy > 0 {
                        particles[i].vy *= -0.55
                        particles[i].va *= 0.6
                    }
                }
            }
            i -= 1
        }
        if shake > FXConfig.shakeCutoff {
            shake *= pow(FXConfig.shakeDecayPerFrame, f)
        } else {
            shake = 0
        }
        if particles.isEmpty && shake == 0 {
            // 閒置：停掉 TimelineView
            DispatchQueue.main.async { [weak self] in
                guard let self, self.particles.isEmpty, self.shake == 0 else { return }
                self.isAnimating = false
                self.lastStep = nil
            }
        }
    }

    func shakeOffset() -> CGSize {
        guard shake > 0 else { return .zero }
        return CGSize(width: CGFloat.random(in: -0.5...0.5) * shake,
                      height: CGFloat.random(in: -0.5...0.5) * shake)
    }
}

// MARK: - 粒子繪製層（不可點擊）
struct FXLayer: View {
    @ObservedObject var model: FXModel

    var body: some View {
        TimelineView(.animation(paused: !model.isAnimating)) { timeline in
            Canvas { ctx, _ in
                if model.isAnimating { model.step(timeline.date) }
                for p in model.particles {
                    if p.t < 0 { continue }      // 延遲出現的泡泡
                    let k = CGFloat(p.t / p.life)
                    var c = ctx
                    c.opacity = Double(1 - k * k)
                    switch p.kind {
                    case .spark:
                        var path = Path()
                        path.move(to: CGPoint(x: p.x, y: p.y))
                        path.addLine(to: CGPoint(x: p.x - p.vx * 2.4, y: p.y - p.vy * 2.4))
                        if p.outlined && p.color == .white {
                            c.stroke(path, with: .color(FXConfig.inkColor.opacity(0.5)),
                                     style: StrokeStyle(lineWidth: p.size * (1 - k) + 2, lineCap: .round))
                        }
                        c.stroke(path, with: .color(p.color),
                                 style: StrokeStyle(lineWidth: p.size * (1 - k) + 0.5, lineCap: .round))
                    case .ring:
                        let r = p.size + k * p.grow
                        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                        if p.outlined {
                            c.stroke(Path(ellipseIn: rect), with: .color(FXConfig.inkColor.opacity(0.4)),
                                     lineWidth: 5 * (1 - k) + 2.5)
                        }
                        c.stroke(Path(ellipseIn: rect), with: .color(p.color),
                                 lineWidth: 5 * (1 - k) + 0.5)
                    case .keycap:
                        var kc = c
                        kc.translateBy(x: p.x, y: p.y)
                        kc.rotate(by: .radians(Double(p.angle)))
                        let rect = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size)
                        kc.fill(Path(rect), with: .color(.white))
                        kc.stroke(Path(rect), with: .color(FXConfig.inkColor), lineWidth: 2)
                        kc.draw(kc.resolve(Text(p.text).font(.system(size: p.size * 0.6, weight: .bold))
                            .foregroundColor(FXConfig.inkColor)), at: CGPoint(x: 0, y: 1))
                    case .bubble:
                        let r = p.size * (1 + k * 0.5)
                        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                        c.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35)))
                        c.stroke(Path(ellipseIn: rect), with: .color(FXConfig.inkColor.opacity(0.3)), lineWidth: 4)
                        c.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2.5)
                        let dot = CGRect(x: p.x - r * 0.35 - r * 0.2, y: p.y - r * 0.35 - r * 0.2,
                                         width: r * 0.4, height: r * 0.4)
                        c.fill(Path(ellipseIn: dot), with: .color(.white))
                    case .bolt:
                        var path = Path()
                        path.addLines(p.pts)
                        c.addFilter(.shadow(color: Color(red: 1, green: 0xD4 / 255, blue: 0x3B / 255), radius: 18))
                        c.stroke(path, with: .color(.white),
                                 style: StrokeStyle(lineWidth: 7 * (1 - k) + 1.5, lineCap: .round, lineJoin: .round))
                    case .line:
                        var path = Path()
                        path.move(to: CGPoint(x: p.x, y: p.y))
                        path.addLine(to: CGPoint(x: p.x2, y: p.y2))
                        let w = p.size * (1 - k) + 1
                        c.stroke(path, with: .color(FXConfig.inkColor.opacity(0.35)),
                                 style: StrokeStyle(lineWidth: w + 3, lineCap: .round))
                        c.stroke(path, with: .color(p.color), style: StrokeStyle(lineWidth: w, lineCap: .round))
                    case .text:
                        if p.outlined {
                            c.addFilter(.shadow(color: FXConfig.inkColor.opacity(0.6), radius: 3, x: 0, y: 1))
                        }
                        let pop = 1 + 0.3 * max(0, 1 - k * 5)
                        let text = Text(p.text).font(.system(size: p.size * pop, weight: .black)).foregroundColor(p.color)
                        c.draw(c.resolve(text), at: CGPoint(x: p.x, y: p.y))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 畫面震動
private struct FXShake: ViewModifier {
    @ObservedObject var model: FXModel

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !model.isAnimating)) { timeline in
            if model.isAnimating { model.step(timeline.date) }
            return content.offset(model.shakeOffset())
        }
    }
}

extension View {
    /// 依 FXModel 的震動量位移整個 view。
    func fxShake(_ model: FXModel) -> some View {
        modifier(FXShake(model: model))
    }
}
