//
//  Untitled.swift
//  iratappu
//
//  Created by chang chiawei on 2025-03-22.
//

import GoogleMobileAds
import UIKit

class AppOpenAdManager: NSObject {
    static let shared = AppOpenAdManager()
    
    private var appOpenAd: AppOpenAd?
    private var isLoadingAd = false
    private let adUnitID = "ca-app-pub-9275380963550837/4969141677" // ← AdMob のユニット ID を入力

    func loadAd() {
        guard !isLoadingAd else { return }
        isLoadingAd = true
        
        AppOpenAd.load(
            with: adUnitID,
            request: Request(),
            completionHandler: { [weak self] (ad: AppOpenAd?, error: Error?) in
                self?.isLoadingAd = false
                if let error = error {
                    print("Ad failed to load: \(error.localizedDescription)")
                    return
                }
                self?.appOpenAd = ad
            }
        )
    }
    
    func showAdIfAvailable() {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                 let rootVC = windowScene.windows.first?.rootViewController,
                 let ad = appOpenAd else {
               print("Ad not ready")
               return
           }

        ad.present(from: rootVC)
        self.appOpenAd = nil
    }
}
