//
//  Untitled.swift
//  iratappu
//
//  Created by chang chiawei on 2025-03-22.
//

import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: AdSizeBanner)
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        bannerView.load(Request()) // ✅ 確保使用新版 GADRequest
        return bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
