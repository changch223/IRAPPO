import UIKit

/// 自訂照片只存在本機：Application Support 裡的檔案（不是 UserDefaults），不備份、不分享。
struct PhotoStore {
    let directory: URL

    static let shared: PhotoStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return PhotoStore(directory: base.appendingPathComponent("IRAPPO", isDirectory: true))
    }()

    var fileURL: URL { directory.appendingPathComponent("customPhoto.png") }

    /// 最長邊上限（像素）
    static let maxSide: CGFloat = 1024

    /// 轉成方向 .up（pngData 會丟掉方向資訊，不先轉的話重新載入可能是橫的）並縮到最長邊 maxSide。
    static func normalized(_ image: UIImage, maxSide: CGFloat = PhotoStore.maxSide) -> UIImage {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        let ratio = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (pixelW * ratio).rounded(), height: (pixelH * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))     // draw 會套用 imageOrientation
        }
    }

    func save(_ image: UIImage) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = Self.normalized(image).pngData() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true          // 照片不進 iCloud / iTunes 備份
        try? url.setResourceValues(values)
    }

    func load() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}

/// 遊戲設定的持久化：模式、起始角色、是否使用自訂照片（照片本身存檔）。
/// 武器、聲音、解鎖、提示旗標各自已經持久化。
final class SettingsStore {
    private let defaults: UserDefaults
    let photos: PhotoStore

    enum Key {
        static let mode = "gameMode"
        static let startingCharacter = "startingCharacter"
        static let useCustomPhoto = "useCustomPhoto"
    }

    init(defaults: UserDefaults = .standard, photos: PhotoStore = .shared) {
        self.defaults = defaults
        self.photos = photos
    }

    var mode: GameMode {
        get { defaults.string(forKey: Key.mode) == "mokugyo" ? .mokugyo : .rage }
        set { defaults.set(newValue == .mokugyo ? "mokugyo" : "rage", forKey: Key.mode) }
    }

    var startingCharacter: Int {
        get { max(0, defaults.integer(forKey: Key.startingCharacter)) }
        set { defaults.set(newValue, forKey: Key.startingCharacter) }
    }

    var useCustomPhoto: Bool {
        get { defaults.bool(forKey: Key.useCustomPhoto) }
        set { defaults.set(newValue, forKey: Key.useCustomPhoto) }
    }

    /// nil＝刪除檔案
    func savePhoto(_ image: UIImage?) {
        if let image { try? photos.save(image) } else { photos.delete() }
    }

    /// 只有「使用自訂照片」開著才還原
    func loadPhoto() -> UIImage? {
        useCustomPhoto ? photos.load() : nil
    }
}
