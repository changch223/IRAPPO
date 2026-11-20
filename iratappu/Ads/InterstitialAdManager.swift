import GoogleMobileAds
import UIKit

enum AdConfig {
    /// 每幾次結算才出一次全螢幕廣告
    static let resultsPerAd = 3
    /// 呼叫 present 後多久還沒開始顯示就放棄、直接出結算頁（秒）
    static let presentTimeout: TimeInterval = 1.5

    /// 全螢幕廣告單元 ID。Debug 用 Google 測試 ID，Release 用正式 ID。
    #if DEBUG
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"   // Google 測試 ID
    #else
    static let interstitialUnitID = "ca-app-pub-9275380963550837/7595394220"   // 正式：インタースティシャル
    #endif
}

/// 全螢幕廣告：只在「一輪結束、結算頁出現之前」顯示（每 `AdConfig.resultsPerAd` 次結算一次，
/// 且廣告已載入）。廣告關掉後才出結算頁；沒有廣告就直接出結算頁。
/// 結算頁可互動時、按下「再來一輪」之後都不會出廣告。
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {
    static let shared = InterstitialAdManager()

    private var ad: InterstitialAd?
    private var isLoading = false
    private var pendingCompletion: (() -> Void)?
    private var didStartPresenting = false

    func loadIfNeeded() {
        guard !AppEnvironment.isRunningTests, !AdConfig.interstitialUnitID.isEmpty, ad == nil, !isLoading else { return }
        isLoading = true
        InterstitialAd.load(with: AdConfig.interstitialUnitID, request: Request()) { [weak self] loaded, error in
            self?.isLoading = false
            if let error {
                print("Interstitial failed to load: \(error.localizedDescription)")
                return
            }
            self?.ad = loaded
            self?.ad?.fullScreenContentDelegate = self
        }
    }

    /// 有載入好的廣告就顯示，關掉（或顯示失敗）後呼叫 completion；沒有廣告就立刻呼叫。
    func present(completion: @escaping () -> Void) {
        guard !AppEnvironment.isRunningTests, let ad,
              let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController else {
            completion()
            return
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        do {
            try ad.canPresent(from: top)
        } catch {
            self.ad = nil
            completion()
            return
        }
        pendingCompletion = completion
        didStartPresenting = false
        ad.present(from: top)
        self.ad = nil
        // 安全逾時：廣告一直沒開始顯示（沒有 willPresent 回呼）就直接出結算頁
        DispatchQueue.main.asyncAfter(deadline: .now() + AdConfig.presentTimeout) { [weak self] in
            guard let self, !self.didStartPresenting else { return }
            self.finishPending()
        }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        didStartPresenting = true
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        self.ad = nil
        recoverMedia()
        finishPending()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        self.ad = nil
        recoverMedia()
        finishPending()
    }

    /// 可重複呼叫：只會執行一次 completion
    private func finishPending() {
        let done = pendingCompletion
        pendingCompletion = nil
        done?()
    }

    /// 廣告可能改動 audio session 或中斷引擎：關掉廣告後重設 .ambient、重啟音訊與震動引擎
    private func recoverMedia() {
        AudioEngine.shared.prepare()
        HapticsEngine.shared.prepare()
    }
}
