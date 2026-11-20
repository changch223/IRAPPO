import Foundation

/// 全螢幕白閃的節流（光敏考量）。純值型別，時間由呼叫端傳入，方便測試。
/// - 過去 1 秒內的閃光起點最多 3 次（滑動視窗）。
/// - 武器白閃之間至少隔 0.333 秒。
/// - KO 白閃優先：和武器白閃幾乎同時（相差 < 0.05 秒）時，覆蓋那一次，算同一次閃光、同一個起點；
///   其他情況 KO 白閃也算進 3 次配額，額度不夠就不閃。
struct FlashLimiter {
    static let window: TimeInterval = 1
    static let maxPerWindow = 3
    static let minWeaponInterval: TimeInterval = 0.333
    static let mergeWindow: TimeInterval = 0.05

    /// 視窗內已閃光的起點（每次閃光都記錄）
    private(set) var starts: [TimeInterval] = []
    private var lastWasKO = false

    /// 要閃的話回傳 true（並記下這次閃光）
    mutating func request(now t: TimeInterval, ko: Bool) -> Bool {
        starts.removeAll { t - $0 >= Self.window }
        if ko, !lastWasKO, let last = starts.last, t - last < Self.mergeWindow {
            lastWasKO = true
            return true
        }
        guard starts.count < Self.maxPerWindow else { return false }
        if !ko, let last = starts.last, t - last < Self.minWeaponInterval { return false }
        starts.append(t)
        lastWasKO = ko
        return true
    }
}
