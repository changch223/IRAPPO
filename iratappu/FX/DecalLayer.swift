import SwiftUI

// MARK: - 殘留痕跡（鞋印、裂痕、焦痕）
// 畫在角色上方、粒子層下方的獨立圖層，擊退時（延遲）、新一輪、結算時清空。

enum DecalConfig {
    static let maxDecals = 150
    static let koClearDelay: TimeInterval = 0.45
}

enum Decal {
    case footprint(center: CGPoint, rotation: Double, a: CGFloat, b: CGFloat)
    case crack(lines: [[CGPoint]])
    case scorch(center: CGPoint, radius: CGFloat)
}

final class DecalModel: ObservableObject {
    @Published private(set) var decals: [Decal] = []

    func add(_ decal: Decal) {
        decals.append(decal)
        if decals.count > DecalConfig.maxDecals {
            decals.removeFirst(decals.count - DecalConfig.maxDecals)
        }
    }

    func clear() {
        if !decals.isEmpty { decals = [] }
    }
}

struct DecalLayer: View {
    @ObservedObject var model: DecalModel

    var body: some View {
        Canvas { ctx, _ in
            for d in model.decals {
                switch d {
                case .footprint(let c, let rot, let a, let b):
                    var g = ctx
                    g.translateBy(x: c.x, y: c.y)
                    g.rotate(by: .radians(rot))
                    let oval = Path(ellipseIn: CGRect(x: -a, y: -b, width: a * 2, height: b * 2))
                    g.fill(oval, with: .color(Color(red: 200 / 255, green: 30 / 255, blue: 45 / 255).opacity(0.3)))
                    var lace = Path()
                    lace.move(to: CGPoint(x: -a * 0.75, y: -b * 0.1))
                    lace.addLine(to: CGPoint(x: 0, y: -b * 0.62))
                    lace.addLine(to: CGPoint(x: a * 0.75, y: -b * 0.1))
                    g.stroke(lace, with: .color(Color(red: 200 / 255, green: 30 / 255, blue: 45 / 255).opacity(0.6)),
                             style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                case .crack(let lines):
                    for line in lines {
                        var path = Path()
                        path.addLines(line)
                        ctx.stroke(path, with: .color(FXConfig.inkColor.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
                        ctx.stroke(path, with: .color(.white.opacity(0.95)),
                                   style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    }
                case .scorch(let c, let r):
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect),
                             with: .radialGradient(Gradient(colors: [Color(red: 20 / 255, green: 10 / 255, blue: 12 / 255).opacity(0.5),
                                                                     Color(red: 20 / 255, green: 10 / 255, blue: 12 / 255).opacity(0)]),
                                                   center: c, startRadius: 0, endRadius: r))
                }
            }
        }
        .drawingGroup()      // 靜態內容，攤平成一張圖
        .allowsHitTesting(false)
    }
}
