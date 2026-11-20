import SwiftUI

// MARK: - 版面常數（UI-SPEC 第 2 節，pt 以 402pt 寬為準，實際乘上 uiScale）

enum MainLayout {
    static let topInset: CGFloat = 8          // 上方貼 safe area 再加
    static let iconSize: CGFloat = 57
    static let hpTop: CGFloat = 21
    static let hpHeight: CGFloat = 26
    static let footHeight: CGFloat = 32
    static let footBottom: CGFloat = 8
    static let footTop: CGFloat = 8
    static let bannerHeight: CGFloat = 50      // 不乘 uiScale（AdMob banner 固定高）

    /// 舞台區（hp 列與下方按鈕之間）在畫面座標的位置
    static func stageRect(size: CGSize, insets: EdgeInsets, k: CGFloat) -> CGRect {
        let minY = insets.top + (topInset + iconSize + hpTop + hpHeight) * k
        let maxY = size.height - insets.bottom - bannerHeight - (footBottom + footHeight + footTop) * k
        return CGRect(x: 0, y: minY, width: size.width, height: max(0, maxY - minY))
    }
}

// MARK: - 舞台版面：連擊字級、角色大小與位置

/// combo 區塊的底緣就是角色可用的上限。舞台不夠高時依序：縮小 combo 字級、角色中心往下調、最後才縮小角色框。
struct StageGeometry: Equatable {
    let region: CGRect
    /// combo 數字字級（pt，已乘 k）
    let comboFont: CGFloat
    /// 角色框邊長（不含魔王的 1.14 倍）
    let faceSide: CGFloat
    /// 角色中心（畫面座標）
    let faceCenter: CGPoint

    // 以 402pt 寬為準的 pt（乘 k）
    static let comboTop: CGFloat = 13
    static let comboLabel: CGFloat = 28          // 4 + 怒氣等級文字 24
    static let hintReserve: CGFloat = 52         // 8 + 提示膠囊 44
    static let comboFonts: [CGFloat] = [143, 120, 100]
    static let sideShrinks: [CGFloat] = [1, 0.92, 0.85]
    /// 角色框往上、往下最遠的延伸（相對 faceSide，含魔王 1.14 倍與名牌、頭盔）
    static let reachTop: CGFloat = 0.67
    static let reachBottom: CGFloat = 0.57

    init(region: CGRect, k: CGFloat) {
        self.region = region
        let base = GameSession.faceSide(in: region.size)
        let h = region.height
        var chosen: (font: CGFloat, side: CGFloat, center: CGFloat)?
        search: for shrink in Self.sideShrinks {
            let side = base * shrink
            for f in Self.comboFonts {
                let font = f * k
                let top = (Self.comboTop + Self.comboLabel) * k + font + Self.reachTop * side
                let bottom = Self.reachBottom * side + Self.hintReserve * k
                if top + bottom <= h {
                    let center = min(max(h * SessionConfig.faceCenterY, top), h - bottom)
                    chosen = (font, side, center)
                    break search
                }
            }
        }
        if chosen == nil {
            // 怎麼縮都放不下：用最小的，角色貼著 combo 下緣
            let side = base * (Self.sideShrinks.last ?? 1)
            let font = (Self.comboFonts.last ?? 100) * k
            chosen = (font, side, (Self.comboTop + Self.comboLabel) * k + font + Self.reachTop * side)
        }
        comboFont = chosen!.font
        faceSide = chosen!.side
        faceCenter = CGPoint(x: region.midX, y: region.minY + chosen!.center)
    }
}

// MARK: - 描邊文字（白字加 ink 描邊，用多層偏移模擬）

struct OutlinedText: View {
    let text: String
    let font: Font
    let fill: Color
    let stroke: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let a = Double(i) / 12 * 2 * .pi
                Text(text).font(font).foregroundColor(stroke)
                    .offset(x: CGFloat(cos(a)) * width, y: CGFloat(sin(a)) * width)
            }
            Text(text).font(font).foregroundColor(fill)
        }
    }
}

// MARK: - HUD：血條列

/// 左：第 N 個　中：血條　右：血量。木魚模式整列不顯示但保留高度。
struct HPRow: View {
    @ObservedObject var session: GameSession
    @Environment(\.uiScale) private var k

    var body: some View {
        let boss = session.mode == .rage && session.enemy.kind == .boss
        HStack(spacing: 10 * k) {
            Text(session.enemyLabel)
                .uiFont(16, .black)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
                .transaction { $0.animation = nil }       // 換對手時文字不交叉淡化
            EnemyHPBar(ratio: session.enemy.maxHP > 0 ? session.enemy.hp / session.enemy.maxHP : 0, boss: boss)
            Text("\(Int(session.enemy.hp.rounded(.up)))")
                .uiFont(20, .black, number: true)
                .fixedSize()
                .frame(minWidth: 42 * k, alignment: .trailing)
                .layoutPriority(2)
                .transaction { $0.animation = nil }
        }
        .foregroundColor(Theme.ink)
        .padding(.horizontal, 26 * k)
        .frame(height: MainLayout.hpHeight * k)
        .opacity(session.mode == .rage ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(session.mode != .rage)
    }
}

struct EnemyHPBar: View {
    let ratio: Double
    let boss: Bool
    @Environment(\.uiScale) private var k

    var body: some View {
        let h = (boss ? 22 : 14) * k
        GeometryReader { geo in
            let w = max(0, geo.size.width * min(max(ratio, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.16))
                Group {
                    if boss {
                        Canvas { ctx, size in
                            // -45° 斜紋：ink 與 ink 76% 混 hot，各 10pt 寬交替
                            let stripe = 10 * k
                            let alt = Color(hex: 0x1C1014).mix(with: Theme.hot, by: 0.24)
                            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink))
                            var x: CGFloat = -size.height
                            var odd = false
                            while x < size.width + size.height {
                                if odd {
                                    var p = Path()
                                    p.move(to: CGPoint(x: x, y: size.height))
                                    p.addLine(to: CGPoint(x: x + stripe, y: size.height))
                                    p.addLine(to: CGPoint(x: x + stripe + size.height, y: 0))
                                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                                    p.closeSubpath()
                                    ctx.fill(p, with: .color(alt))
                                }
                                odd.toggle()
                                x += stripe
                            }
                        }
                    } else {
                        Theme.ink
                    }
                }
                .frame(width: w)
                .clipShape(Capsule())
                .animation(.easeOut(duration: 0.18), value: ratio)
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.ink, lineWidth: boss ? 2.6 * k : 0))
        }
        .frame(height: h)
    }
}

private extension Color {
    /// 在 sRGB 空間往另一個顏色混 t 比例
    func mix(with other: Color, by t: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = CGFloat(t)
        return Color(.sRGB, red: Double(ar + (br - ar) * t), green: Double(ag + (bg - ag) * t),
                     blue: Double(ab + (bb - ab) * t), opacity: 1)
    }
}

// MARK: - 蓄力時角色發抖

private struct ChargeShake: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !active)) { _ in
            content
                .offset(x: active ? CGFloat.random(in: -2.5...2.5) : 0, y: active ? CGFloat.random(in: -2.5...2.5) : 0)
                .rotationEffect(.degrees(active ? Double.random(in: -1.5...1.5) : 0))
        }
    }
}

// MARK: - FEVER：角色每 0.5 秒黃色光暈脈動一次

private struct FeverGlow: ViewModifier {
    let active: Bool
    let reduceMotion: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: Theme.spark.opacity(active && on ? 1 : 0), radius: 16)
            .onChange(of: active, initial: true) { _, isActive in
                if isActive && !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.25).repeatForever(autoreverses: true)) { on = true }
                } else {
                    withAnimation(.none) { on = false }
                }
            }
    }
}

// MARK: - 魔王光暈（角色的 background，不參與版面）

private struct BossAura: View {
    let side: CGFloat
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        let d = side * 1.28
        Circle()
            .fill(RadialGradient(colors: [Theme.ink.opacity(0.55), .clear], center: .center,
                                 startRadius: 0, endRadius: d / 2))
            .frame(width: d, height: d)
            .scaleEffect(pulse ? 1.12 : 1)
            .opacity(pulse ? 0.65 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

private struct Spinning: ViewModifier {
    let reduceMotion: Bool
    @State private var angle = 0.0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}

// MARK: - 打擊區

/// 整個螢幕都是打擊區：背景熱度、全螢幕觸控層（最底）、角色與特效（不攔截觸控）。
/// 按鈕由 ContentView 疊在上面。
struct StageView: View {
    @ObservedObject var session: GameSession
    @ObservedObject var fx: FXModel
    let reduceMotion: Bool
    /// 整個螢幕（含 safe area）的大小
    let size: CGSize
    /// 舞台區（hp 列與下方按鈕之間）在畫面座標的位置
    let region: CGRect

    @Environment(\.uiScale) private var k
    /// 臉圖裁好時會更新（還沒裁好先顯示原圖）
    @ObservedObject private var crops = FaceCrop.shared
    /// 手勢被取消時會自動回到 false（onEnded 不會被呼叫）
    @GestureState private var gestureActive = false

    var body: some View {
        let moku = session.mode == .mokugyo
        // 角色大小與位置每次都從傳進來的 region 算，不靠 session 上存的舊值
        let geo = StageGeometry(region: region, k: k)
        ZStack {
            // 背景熱度（鋪滿整個螢幕）
            (moku ? Theme.woodBg : Theme.heatColor(session.heat))
                .animation(session.phase == .cooling ? .linear(duration: GameConfig.coolingDuration)
                                                     : .easeOut(duration: 0.15),
                           value: session.heat)

            // 觸控層：最底下，按鈕在上面
            touchLayer

            // 角色與特效：全部不攔截觸控；任何裝飾都不能影響版面大小
            ZStack {
                ComboBlock(session: session, geo: geo)

                face(geo)

                // 殘留痕跡（角色上方、粒子層下方）
                DecalLayer(model: session.decals)

                ForEach(session.ghosts) { ghost in
                    GhostFace(ghost: ghost, side: geo.faceSide, stage: size)
                        .position(geo.faceCenter)
                }

                if let ko = session.koText {
                    KOText(text: ko.text, reduceMotion: reduceMotion)
                        .frame(width: region.width)
                        .position(x: region.midX, y: region.minY + region.height * 0.36)
                        .id(ko.id)
                }

                if session.isCharging {
                    ChargeRing(session: session, geo: geo)
                }

                StageBottom(session: session, coach: session.coach)
                    .frame(width: region.width, height: region.height, alignment: .bottom)
                    .position(x: region.midX, y: region.midY)

                if let spot = session.weakSpot {
                    WeakSpotView(spot: spot, reduceMotion: reduceMotion)
                }

                FXLayer(model: fx)
            }
            .frame(width: size.width, height: size.height)
            .fxShake(fx)
            .allowsHitTesting(false)

            // 白閃（雷電與擊退共用）
            Color.white.opacity(session.flash)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "fxStage")
        .onAppear { session.setLayout(screen: size, geometry: geo) }
        .onChange(of: size) { _, _ in session.setLayout(screen: size, geometry: StageGeometry(region: region, k: k)) }
        .onChange(of: geo) { _, newGeo in session.setLayout(screen: size, geometry: newGeo) }
    }

    private var touchLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("fxStage"))
                    .updating($gestureActive) { _, state, _ in state = true }
                    .onChanged { v in
                        // 以引擎的按壓狀態為準：被取消 / 新一輪重設後，下一次觸碰一定重新開始
                        if !session.isPressing {
                            session.pressBegan(at: v.startLocation)
                        }
                        session.pressMoved(to: v.location)
                    }
                    .onEnded { v in
                        session.pressEnded(at: v.location)
                    }
            )
            .onChange(of: gestureActive) { _, active in
                // 手勢結束但 onEnded 沒處理到（被來電、Siri、系統搶走）→ 取消按壓。
                // 延到下一個 run loop，讓正常的 onEnded 先跑完。
                guard !active else { return }
                let began = session.pressBeganUptime
                DispatchQueue.main.async {
                    // 同一次按壓還沒被 onEnded 收掉才取消（避免誤傷剛開始的下一次按壓）
                    if session.isPressing && session.pressBeganUptime == began {
                        session.pressCancelled()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("stage_label"))
            .accessibilityHint(L("stage_hint"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { session.performAccessibilityTap() }
    }

    // MARK: 角色

    @ViewBuilder
    private func face(_ geo: StageGeometry) -> some View {
        let side = geo.faceSide
        let t = session.faceTransform
        let moku = session.mode == .mokugyo
        let rage = session.mode == .rage
        let boss = rage && session.enemy.kind == .boss
        let hpRatio = session.enemy.maxHP > 0 ? session.enemy.hp / session.enemy.maxHP : 1
        let dmg1 = rage && hpRatio < 0.66
        let dmg2 = rage && hpRatio < 0.33
        let fever = rage && session.phase == .fighting && session.multiplier >= 2

        session.faceImage(for: session.enemy)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            // 頭盔：字級 = 框 × 0.36，在框頂上方 12%
            .overlay(alignment: .top) {
                if rage && session.enemy.hasArmor {
                    Text("🪖")
                        .font(.system(size: side * 0.36))
                        .offset(y: -side * 0.12)
                }
            }
            // 魔王名牌：ink 底、spark 字，在框頂上方 9%
            .overlay(alignment: .top) {
                if boss {
                    Text(L("boss_badge"))
                        .uiFont(22, .black)
                        .tracking(22 * k * 0.2)
                        .foregroundColor(Theme.spark)
                        .padding(.horizontal, 12 * k).padding(.vertical, 4 * k)
                        .background(RoundedRectangle(cornerRadius: 6 * k).fill(Theme.ink))
                        .fixedSize()
                        .offset(y: -side * 0.09)
                }
            }
            // 傷痕記號：血量 < 66% 🩹、< 33% 再加 💫（換新對手時隨 .id 重置）
            .overlay(alignment: .topLeading) {
                Text("🩹")
                    .font(.system(size: 47 * k))
                    .rotationEffect(.degrees(-24))
                    .offset(x: side * 0.08, y: side * 0.22)
                    .opacity(dmg1 ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: dmg1)
            }
            .overlay(alignment: .topTrailing) {
                Text("💫")
                    .font(.system(size: 47 * k))
                    .modifier(Spinning(reduceMotion: reduceMotion))
                    .offset(x: -side * 0.04, y: -side * 0.04)
                    .opacity(dmg2 ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: dmg2)
            }
            .modifier(FeverGlow(active: fever, reduceMotion: reduceMotion))
            .scaleEffect(t.scale, anchor: moku ? UnitPoint(x: 0.5, y: 0.7) : .center)
            .rotationEffect(.degrees(t.rotation))
            .offset(x: t.dx)
            .scaleEffect(session.isCharging ? 0.91 : 1)
            .animation(.easeOut(duration: 0.12), value: session.isCharging)
            .modifier(ChargeShake(active: session.isCharging && !reduceMotion))
            // 光暈是 background：不參與版面，角色中心點不會因為魔王而位移
            .background {
                if boss { BossAura(side: side, reduceMotion: reduceMotion) }
            }
            .scaleEffect(boss ? SessionConfig.bossFaceScale : moku ? SessionConfig.mokugyoFaceScale : 1)
            .id(session.faceID)
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .identity))
            .position(geo.faceCenter)
    }
}

// MARK: - 連擊數字（在角色後面）

private struct ComboBlock: View {
    @ObservedObject var session: GameSession
    let geo: StageGeometry
    @Environment(\.uiScale) private var k

    var body: some View {
        let region = geo.region
        let moku = session.mode == .mokugyo
        let live = session.phase == .fighting || session.phase == .cooling
        let fever = !moku && session.phase == .fighting && session.multiplier >= 2
        let value = moku ? session.merit : session.combo
        let font = Font.system(size: geo.comboFont, weight: .black, design: .rounded).monospacedDigit()
        VStack(spacing: 0) {
            Group {
                if moku {
                    Text("\(value)").font(font).foregroundColor(Theme.wood)
                } else if fever {
                    OutlinedText(text: "\(value)", font: font, fill: Theme.spark, stroke: Theme.ink, width: 4 * k)
                } else {
                    Text("\(value)").font(font).foregroundColor(Theme.paper)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(height: geo.comboFont)
            .padding(.horizontal, 12 * k)

            if !moku {
                Text(session.rageText)
                    .uiFont(20, .black)
                    .foregroundColor(Theme.ink)
                    .padding(.top, 4 * k)
            }
        }
        .padding(.top, 13 * k)
        .frame(width: region.width, height: region.height, alignment: .top)
        .position(x: region.midX, y: region.midY)
        .opacity(live ? (session.phase == .cooling ? 0.35 : 1) : 0)
        .animation(.easeOut(duration: 0.2), value: live)
        .animation(.easeOut(duration: 0.2), value: session.phase == .cooling)
        .accessibilityHidden(true)
    }
}

// MARK: - 擊退！

private struct KOText: View {
    let text: String
    let reduceMotion: Bool
    @Environment(\.uiScale) private var k
    @State private var landed = false

    var body: some View {
        OutlinedText(text: text, font: .system(size: 73 * k, weight: .black), fill: Theme.paper,
                     stroke: Theme.ink, width: 3 * k)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 12 * k)
            .rotationEffect(.degrees(-8))
            .scaleEffect(landed ? 1 : 2.4)
            .onAppear {
                if reduceMotion { landed = true; return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { landed = true }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - 舞台底部（同一個位置一次只顯示一樣）

private struct StageBottom: View {
    @ObservedObject var session: GameSession
    @ObservedObject var coach: CoachManager
    @Environment(\.uiScale) private var k

    var body: some View {
        let hasCoach = coach.message != nil || coach.current != nil
        ZStack(alignment: .bottom) {
            // 1. 情境提示膠囊（自己會在沒有提示時是空的）
            CoachCapsule(coach: coach)

            if !hasCoach {
                if session.isCharging {
                    // 2. 蓄力字
                    Text(L("charging_label"))
                        .uiFont(20, .black)
                        .foregroundColor(Theme.ink)
                } else if session.coolingActive {
                    // 3. 冷卻
                    CoolingHint()
                } else if session.phase == .idle && session.result == nil {
                    // 4. 待機提示
                    Text(L("idle_hint"))
                        .uiFont(17, .bold)
                        .foregroundColor(Theme.ink)
                }
            }
        }
        .padding(.bottom, 8 * k)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

private struct CoolingHint: View {
    @Environment(\.uiScale) private var k
    @State private var drained = false

    var body: some View {
        VStack(spacing: 6 * k) {
            Text(L("cooling_label"))
                .uiFont(17, .bold)
                .foregroundColor(Theme.ink)
            // 血條樣式的條：2 秒從滿到空
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.16))
                    Capsule().fill(Theme.ink)
                        .frame(width: drained ? 0 : geo.size.width)
                }
            }
            .frame(height: 14 * k)
        }
        .padding(.horizontal, 39 * k)
        .onAppear {
            withAnimation(.linear(duration: GameConfig.coolingDuration)) { drained = true }
        }
    }
}

// MARK: - 擊退時飛出的舊角色

private struct GhostFace: View {
    let ghost: Ghost
    let side: CGFloat
    let stage: CGSize
    @State private var gone = false

    var body: some View {
        ghost.image
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .scaleEffect(gone ? 0.2 : 1)
            .rotationEffect(.degrees(gone ? ghost.sign * 900 : 0))
            .offset(x: gone ? CGFloat(ghost.sign) * stage.width * 0.9 : 0,
                    y: gone ? -stage.height * 0.9 : 0)
            .opacity(gone ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeIn(duration: SessionConfig.ghostDuration)) { gone = true }
            }
    }
}

// MARK: - 弱點

private struct WeakSpotView: View {
    let spot: WeakSpot
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.spark.opacity(0.45), Theme.spark.opacity(0.1)], center: .center,
                                 startRadius: 0, endRadius: spot.radius))
            .overlay(Circle().stroke(Theme.spark, lineWidth: 4))
            .shadow(color: Theme.spark, radius: 14)
            .frame(width: spot.radius * 2, height: spot.radius * 2)
            .scaleEffect(pulse ? 1.08 : 0.94)
            .position(spot.center)
            .id(spot.until)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

// MARK: - 蓄力環（以角色中心為圓心）

private struct ChargeRing: View {
    @ObservedObject var session: GameSession
    let geo: StageGeometry
    @Environment(\.uiScale) private var k

    var body: some View {
        TimelineView(.animation) { _ in
            let held = GameSession.now() - session.pressBeganUptime
            let progress = min(held / GameConfig.chargeRingFull, 1)
            let d = geo.faceSide * 1.24
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.6 * k, lineCap: .butt))
                .rotationEffect(.degrees(-90))      // 從 12 點鐘方向順時針
                .frame(width: d, height: d)
                .position(geo.faceCenter)
        }
        .allowsHitTesting(false)
    }
}
