import UIKit
import SwiftUI
import Combine

/// 臉圖裁掉透明邊（alpha bbox，四周各留 6%），結果快取在記憶體。
/// Face/*.png 是 1000×1000，但臉只佔中間 21–35%；不裁的話角色框再大臉也不會變大。
///
/// 裁圖都在背景佇列做，主執行緒的 body 只查快取：還沒裁好就先顯示原圖，裁好後 `revision` 變動、畫面更新。
final class FaceCrop: ObservableObject {
    static let shared = FaceCrop()

    static let margin: CGFloat = 0.06
    /// 裁好後重畫成小圖的長邊（px）。重畫之後不再參照 cropping 的整張原圖。
    static let maxSide: CGFloat = 600
    private static let alphaThreshold: UInt8 = 8

    /// 每裁好一張加一，畫面觀察它來更新
    @Published private(set) var revision = 0

    private var cache: [String: UIImage] = [:]
    private var pending: Set<String> = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "irappo.facecrop", qos: .userInitiated)

    static let assetNames: [String] =
        (1...GameConfig.totalCharacters).map { "face\($0)" } + (1...3).map { "mokugyo\($0)" }

    /// App 啟動後在背景把所有臉圖與木魚圖預先裁好
    static func preload() {
        for name in assetNames { shared.request(name) }
    }

    /// 裁好的圖；還沒裁好回傳 nil（並排進背景佇列）。不會在呼叫的執行緒上做裁切。
    func cached(_ name: String) -> UIImage? {
        lock.lock()
        let hit = cache[name]
        lock.unlock()
        if hit == nil { request(name) }
        return hit
    }

    /// 給 SwiftUI 用：裁好的圖，還沒好就先用原圖
    static func image(named name: String) -> Image {
        if let ui = shared.cached(name) { return Image(uiImage: ui) }
        return Image(name)
    }

    private func request(_ name: String) {
        lock.lock()
        if cache[name] != nil || pending.contains(name) { lock.unlock(); return }
        pending.insert(name)
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            let result = UIImage(named: name).map { Self.crop($0) }
            self.lock.lock()
            self.pending.remove(name)
            if let result { self.cache[name] = result }
            self.lock.unlock()
            if result != nil {
                DispatchQueue.main.async { self.revision += 1 }
            }
        }
    }

    /// 自訂照片等：在背景裁好再回到主執行緒
    static func cropAsync(_ image: UIImage, completion: @escaping (UIImage) -> Void) {
        shared.queue.async {
            let cropped = crop(image)
            DispatchQueue.main.async { completion(cropped) }
        }
    }

    /// 裁掉透明邊並重畫成長邊 ≤ maxSide 的小圖。整張都不透明（或全透明）就只縮小。
    /// 不要在主執行緒呼叫。
    static func crop(_ image: UIImage) -> UIImage {
        // 方向不是 up 或太大的先正規化（縮到長邊 1024）
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        let upright = (image.imageOrientation == .up && longest <= PhotoStore.maxSide)
            ? image : PhotoStore.normalized(image)
        guard let cg = upright.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        var rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let box = opaqueBounds(of: cg) {
            let padX = box.width * margin, padY = box.height * margin
            let minX = max(0, box.minX - padX), minY = max(0, box.minY - padY)
            let maxX = min(w, box.maxX + padX), maxY = min(h, box.maxY + padY)
            let r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
            if r.width > 0, r.height > 0 { rect = r }
        }
        guard let part = cg.cropping(to: rect) else { return upright }
        // 重畫成小圖：釋放 cropping 參照的整張原圖
        let ratio = min(1, maxSide / max(rect.width, rect.height))
        let target = CGSize(width: max(1, (rect.width * ratio).rounded()),
                            height: max(1, (rect.height * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIImage(cgImage: part).draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// 不透明範圍（像素）。nil＝找不到。
    static func opaqueBounds(of cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = data.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var minX = w, maxX = -1, minY = h, maxY = -1
        data.withUnsafeBufferPointer { p in
            for y in 0..<h {
                let row = y * w
                var firstX = -1, lastX = -1
                for x in 0..<w where p[row + x] > alphaThreshold {
                    if firstX < 0 { firstX = x }
                    lastX = x
                }
                if firstX >= 0 {
                    minX = min(minX, firstX); maxX = max(maxX, lastX)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
