import SwiftUI
import SwiftData
import Combine
import GoogleMobileAds
import StoreKit
import PhotosUI
import Vision
import UIKit
import CoreImage

// MARK: - 自動去背功能
extension CGImagePropertyOrientation {
    // 將 UIImage.Orientation 轉為 Vision 的 CGImagePropertyOrientation
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

/// 去背函式：先用 Vision 做人像分割，再將遮罩縮放到與原圖同大小，最後用 CIBlendWithMask 去背，
/// 並將結果縮小 1.5 倍。
func removeBackground(from image: UIImage, completion: @escaping (UIImage?) -> Void) {
    guard let cgImage = image.cgImage else {
        completion(nil)
        return
    }
    
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    request.usesCPUOnly = false // 可使用 GPU 加速
    
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
    
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try handler.perform([request])
            guard let pixelBuffer = request.results?.first?.pixelBuffer else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let ciImage = CIImage(cgImage: cgImage)
            let maskCIImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // 將 mask 根據原圖大小做縮放
            let scaleX = ciImage.extent.width  / maskCIImage.extent.width
            let scaleY = ciImage.extent.height / maskCIImage.extent.height
            let scaledMask = maskCIImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
            
            // 使用 CIBlendWithMask 做去背
            let maskedImage = ciImage.applyingFilter("CIBlendWithMask", parameters: [
                "inputMaskImage": scaledMask
            ])
            
            // 將去背後的結果縮小 1.5 倍
            let scaledDownImage = maskedImage.transformed(by: CGAffineTransform(scaleX: 1/3, y: 1/3))
            
            let context = CIContext()
            if let outputCGImage = context.createCGImage(scaledDownImage, from: scaledDownImage.extent) {
                let result = UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
                DispatchQueue.main.async {
                    completion(result)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        } catch {
            print("Vision error: \(error)")
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }
}

// MARK: - ImagePicker 實作（包含去背功能）
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool  // 控制圖片選取器顯示
    var onCancel: () -> Void = {}   // 沒有選照片就關掉時

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1  // 限制只選一張圖片
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                DispatchQueue.main.async { self.parent.onCancel() }
                return
            }
            
            provider.loadObject(ofClass: UIImage.self) { image, error in
                if let uiImage = image as? UIImage {
                    removeBackground(from: uiImage) { processedImage in
                        DispatchQueue.main.async {
                            // 去背失敗就用原圖，但先縮到長邊 1024（也順便轉正方向）
                            self.parent.image = processedImage ?? PhotoStore.normalized(uiImage)
                        }
                    }
                }
            }
        }
    }
}

class AppLaunchCounterManager: ObservableObject {
    static let shared = AppLaunchCounterManager()
    
    @AppStorage("todayAppLaunchCount") var todayAppLaunchCount: Int = 0
    
    private init() {}
    
    func increment() {
        todayAppLaunchCount += 1
        print("App launch count incremented to \(todayAppLaunchCount)")
    }
}

/// 上方與下方的按鈕：live（打擊、冷卻）時 0.25 秒淡出而且不能點；結算頁出現時不能點。
private struct ChromeFade<Content: View>: View {
    @ObservedObject var session: GameSession
    @ViewBuilder let content: () -> Content

    var body: some View {
        let visible = session.phase == .idle || session.result != nil
        let enabled = session.phase == .idle && session.result == nil
        content()
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(enabled)
            .animation(.easeOut(duration: 0.25), value: visible)
    }
}

/// 上方：紀錄鈕 / 模式切換 / 圖鑑鈕（自己觀察 session，不靠外層重新計算）
private struct TopBar: View {
    @ObservedObject var session: GameSession
    @Binding var showStatisticsView: Bool
    @Binding var showDex: Bool
    @Environment(\.uiScale) private var k

    var body: some View {
        HStack(spacing: 8 * k) {
            iconButton("chart.bar", label: L("records_title")) { showStatisticsView = true }
            Spacer(minLength: 0)
            modeSwitch
            Spacer(minLength: 0)
            iconButton("square.grid.2x2", label: L("dex_title")) { showDex = true }
        }
        .padding(.horizontal, 21 * k)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22 * k, weight: .semibold))
                .foregroundColor(Theme.ink)
                .frame(width: MainLayout.iconSize * k, height: MainLayout.iconSize * k)
                .background(Circle().fill(Theme.glass))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton(.rage, L("mode_rage"))
            modeButton(.mokugyo, L("mode_moku"))
        }
        .padding(4.5 * k)
        .background(Capsule().fill(Theme.glass))
        .accessibilityElement(children: .contain)
    }

    private func modeButton(_ mode: GameMode, _ title: String) -> some View {
        let selected = session.mode == mode
        return Button {
            if !selected { session.newRun(mode: mode) }
        } label: {
            Text(title)
                .uiFont(16, .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(selected ? Theme.paper : Theme.ink)
                .padding(.vertical, 8 * k)
                .padding(.horizontal, 14 * k)
                .background(Capsule().fill(selected ? Theme.ink : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 下方：聲音 / 玩法 / 武器 三個 chip
private struct FootBar: View {
    @ObservedObject var session: GameSession
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true
    @Binding var showHelp: Bool
    @Binding var showWeaponSheet: Bool
    @Environment(\.uiScale) private var k

    /// 有武器的解鎖進度 ≥ 80% 就在武器 chip 上亮一個小圓點
    private var weaponNearUnlock: Bool {
        guard !(session.mode == .mokugyo) else { return false }
        return Weapons.all.contains { w in
            guard w.unlock != nil, !session.weaponProgress.isUnlocked(w.id) else { return false }
            let p = session.weaponProgress.progress(for: w)
            return p.required > 0 && p.current * 5 >= p.required * 4
        }
    }

    var body: some View {
        HStack(spacing: 8 * k) {
            chip(soundEnabled ? L("chip_sound_on") : L("chip_sound_off")) { soundEnabled.toggle() }
                .accessibilityLabel(L("sound_toggle"))
                .accessibilityValue(L(soundEnabled ? "sound_on" : "sound_off"))
            Spacer(minLength: 0)
            chip(L("help_button")) { showHelp = true }
            Spacer(minLength: 0)
            // 武器 chip：木魚模式顯示「🪵 木魚」，按了沒反應
            chip((session.mode == .mokugyo) ? L("weapon_chip_mokugyo") : "\(session.weapon.emoji) \(session.weapon.name)") {
                if !(session.mode == .mokugyo) { showWeaponSheet = true }
            }
            .overlay(alignment: .topTrailing) {
                if weaponNearUnlock {
                    Circle().fill(Theme.spark)
                        .frame(width: 11 * k, height: 11 * k)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: 1.5))
                        .offset(x: 2 * k, y: -2 * k)
                }
            }
            .accessibilityLabel(L("weapon_sheet_title"))
        }
        .padding(.horizontal, 23 * k)
        .frame(height: MainLayout.footHeight * k)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .uiFont(16, .bold)
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 6 * k)
                .padding(.horizontal, 13 * k)
                .background(Capsule().fill(Theme.glass))
        }
        .buttonStyle(.plain)
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 給 sheet 與結算頁用的縮放（它們不在 GeometryReader 裡；由主畫面量到寬度後回報）
    @State private var sheetScale: CGFloat = 1
    @State private var showStatisticsView = false
    @State private var showHelp = false
    @State private var showDex = false
    @Environment(\.modelContext) private var modelContext
    /// 這一輪的紀錄（選心情時更新）
    @State private var currentRecord: RunRecord?
    @State private var wasInBackground = false
    
    // 統計與計數（記憶體緩衝，定時寫入）
    @StateObject private var stats = StatsBuffer()
    
    // 音效（持久化）
    @AppStorage("selectedWeapon") private var selectedWeapon: String = WeaponID.fist.rawValue
    @State private var showWeaponSheet = false
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true
    
    // 結算次數（控制全螢幕廣告頻率）
    @AppStorage("resultCount") private var resultCount: Int = 0
    
    @StateObject private var session = GameSession()
    
    // MARK: - 每日重置
    private func checkDateChange() {
        stats.rollDayIfNeeded()
    }
    
    let hasRequestedReviewKey = "hasRequestedReview"
    
    private var isMokugyo: Bool { session.mode == .mokugyo }
    // MARK: - 主畫面
    var body: some View {
        // 外層 GeometryReader 不加 ignoresSafeArea：從這裡讀 safe area 再往內傳。
        // 內層內容撐滿整個螢幕（含 safe area），uiScale 依容器寬度計算（不依螢幕寬）。
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            let size = CGSize(width: outer.size.width + insets.leading + insets.trailing,
                              height: outer.size.height + insets.top + insets.bottom)
            let k = Theme.scale(forWidth: size.width)
            let region = MainLayout.stageRect(size: size, insets: insets, k: k)
            ZStack(alignment: .top) {
                StageView(session: session, fx: session.fx, reduceMotion: reduceMotion,
                          size: size, region: region)

                VStack(spacing: 0) {
                    ChromeFade(session: session) {
                        TopBar(session: session, showStatisticsView: $showStatisticsView, showDex: $showDex)
                            .padding(.top, insets.top + MainLayout.topInset * k)
                    }

                    HPRow(session: session)
                        .padding(.top, MainLayout.hpTop * k)

                    Spacer(minLength: 0)

                    ChromeFade(session: session) {
                        FootBar(session: session, showHelp: $showHelp, showWeaponSheet: $showWeaponSheet)
                            .padding(.top, MainLayout.footTop * k)
                            .padding(.bottom, MainLayout.footBottom * k)
                    }

                    // live 時也照常顯示，不淡出（AdMob 會把隱藏的廣告算成違規）；結算頁也不蓋住它
                    BannerAdView(adUnitID: "ca-app-pub-9275380963550837/6757899905")
                        .frame(height: MainLayout.bannerHeight)
                        .padding(.bottom, insets.bottom)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
            }
            .environment(\.uiScale, k)
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
            .onChange(of: k, initial: true) { _, newValue in sheetScale = newValue }
        }
        .overlay {
            // 結算頁：面板的底部停在 banner 上緣，暗色遮罩也不蓋 banner
            if let summary = session.result {
                ResultView(summary: summary,
                           newWeapons: session.runWeapons,
                           reduceMotion: reduceMotion,
                           onMood: { mood in
                               if let record = currentRecord {
                                   RunRecorder(context: modelContext).setMood(mood, on: record)
                               }
                           },
                           onAgain: playAgain,
                           onFeelingBetter: {
                               if summary.koCount >= 1 { requestReviewOnceIfNeeded() }
                           })
                .padding(.bottom, MainLayout.bannerHeight)
            }
        }
        .environment(\.uiScale, sheetScale)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showStatisticsView) {
            StatisticsView(stats: stats)
                .environment(\.uiScale, sheetScale)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showDex) {
            DexView(session: session) { index in
                showDex = false
                session.startRun(withCharacter: index)
            }
            .environment(\.uiScale, sheetScale)
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
                .environment(\.uiScale, sheetScale)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showWeaponSheet) {
            WeaponSheet(progress: session.weaponProgress, selected: selectedWeapon) { id in
                selectedWeapon = id.rawValue
                showWeaponSheet = false
            }
            .environment(\.uiScale, sheetScale)
            .presentationDetents([.large])
        }
        .onAppear {
            AudioEngine.shared.isEnabled = soundEnabled
            // 先跨日判斷，再計啟動次數（只在這裡計，避免新的一天第一次啟動被歸零）
            checkDateChange()
            AppLaunchCounterManager.shared.increment()
            applySelectedWeapon()
            // 音訊 / 震動的設定都在各自的背景佇列，這裡立刻開始，不會卡主執行緒。
            // 先解碼目前武器的打擊聲與木魚聲，再解碼其餘音檔。
            AudioEngine.shared.prepare(priority: [session.weapon.sound.hit, "kokoko"])
            HapticsEngine.shared.prepare()
            session.reduceMotion = reduceMotion
            session.resultGate = { show in presentResultGate(show) }
            session.onGesture = { stats.recordGesture() }
            session.onCombo = { combo in stats.recordCombo(combo) }
            session.startIfNeeded()
            #if DEBUG
            runUIDemo()
            #endif
        }
        .onChange(of: soundEnabled) { _, newValue in
            AudioEngine.shared.isEnabled = newValue
        }
        .onChange(of: selectedWeapon) { _, _ in
            applySelectedWeapon()
        }
        .onChange(of: reduceMotion) { _, newValue in
            session.reduceMotion = newValue
        }
        .onChange(of: session.result) { _, newValue in
            if let summary = newValue {
                stats.flush()
                // 每輪一筆紀錄
                let weaponId = summary.mode == .mokugyo ? "mokugyo" : session.weapon.id.rawValue
                currentRecord = RunRecorder(context: modelContext).record(summary, weaponId: weaponId)
            } else {
                currentRecord = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AudioEngine.shared.start()
                HapticsEngine.shared.prepare()
                checkDateChange()
                if wasInBackground {
                    wasInBackground = false
                    AppLaunchCounterManager.shared.increment()
                }
            } else {
                // 進背景 / 被打斷：取消按壓、寫入統計
                session.pressCancelled()
                stats.flush()
                session.weaponProgress.flush()
                if phase == .background { wasInBackground = true }
            }
        }
        // 前景時過午夜 / 系統時間大幅改變
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)) { _ in
            checkDateChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .receive(on: RunLoop.main)) { _ in
            checkDateChange()
        }
    }
    
    #if DEBUG
    /// 截圖用：`-uiDemoState idle|fever|armor|boss|bossdmg|damage|charge|cooling|result|resultunlock|mokugyo|dex|weapons|help|records`
    private func runUIDemo() {
        guard let name = UserDefaults.standard.string(forKey: "uiDemoState") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch name {
            case "dex": showDex = true
            case "weapons": showWeaponSheet = true
            case "help": showHelp = true
            case "records":
                // 截圖用：沒有紀錄時塞幾天的假資料
                if ((try? modelContext.fetchCount(FetchDescriptor<RunRecord>())) ?? 0) == 0 {
                    let recorder = RunRecorder(context: modelContext)
                    let kos = [3, 0, 5, 2, 8, 0, 4]
                    for (i, ko) in kos.enumerated() where ko > 0 {
                        let date = Calendar.current.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
                        let summary = RunSummary(mode: .rage, koCount: ko, taps: ko * 30, maxCombo: ko * 9, seconds: 40,
                                                 merit: 0, newBestCombo: nil, newBestRun: nil, unlockedCharacters: [])
                        let r = recorder.record(summary, weaponId: "fist", date: date)
                        recorder.setMood(i % 3, on: r)
                    }
                }
                showStatisticsView = true
            default: session.runDemo(name)
            }
        }
    }
    #endif

    /// 套用選擇的武器；存的 id 無效或還沒解鎖時退回拳頭，並寫回 selectedWeapon（選單才會顯示勾勾）
    private func applySelectedWeapon() {
        session.selectWeapon(rawID: selectedWeapon)
        if session.weapon.id.rawValue != selectedWeapon {
            selectedWeapon = session.weapon.id.rawValue
        }
    }
    
    // MARK: - 結算
    /// 一輪結束（冷卻完）、結算頁出現之前。每 N 次結算且廣告已載入時，先出全螢幕廣告，
    /// 關掉後才顯示結算頁；沒有廣告就直接顯示。結算頁互動中、再來一輪之後都不出廣告。
    private func presentResultGate(_ show: @escaping () -> Void) {
        resultCount += 1
        let n = AdConfig.resultsPerAd
        // 下一次要出廣告的前一次，先預載
        if (resultCount + 1) % n == 0 { InterstitialAdManager.shared.loadIfNeeded() }
        if resultCount % n == 0 {
            InterstitialAdManager.shared.present(completion: show)
        } else {
            show()
        }
    }
    
    private func playAgain() {
        session.newRun()
    }
    
    // 評價邀請：結算頁（有擊退、心情選「好多了」）
    private func requestReviewOnceIfNeeded() {
        let hasRequested = UserDefaults.standard.bool(forKey: hasRequestedReviewKey)
        
        if !hasRequested {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                SKStoreReviewController.requestReview(in: windowScene)
                UserDefaults.standard.set(true, forKey: hasRequestedReviewKey)
                print("✅ 評價請求已發送（僅發送一次）")
            }
        } else {
            print("ℹ️ 已發送過評價請求，這次不重複觸發")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
