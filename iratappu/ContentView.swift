import SwiftUI
import CoreHaptics
import AVFoundation
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
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            
            provider.loadObject(ofClass: UIImage.self) { image, error in
                if let uiImage = image as? UIImage {
                    removeBackground(from: uiImage) { processedImage in
                        DispatchQueue.main.async {
                            self.parent.image = processedImage ?? uiImage
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

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStatisticsView = false
    
    // 統計與計數
    @State private var currentSessionCount = 0
    @AppStorage("todayCount") private var todayCount = 0
    @AppStorage("sevenDayCountsData") private var sevenDayCountsData = Data()
    @AppStorage("todayComboCount") private var todayComboCount: Int = 0
    @AppStorage("todayAppLaunchCount") private var todayAppLaunchCount: Int = 0
    
    // 新增狀態變數：控制是否使用自訂圖片與上傳的圖片
    @State private var useCustomImage: Bool = false
    @State private var customImage: UIImage? = nil
    @State private var showingImagePicker: Bool = false
    
    // ★ 新增：切換功德木魚版本狀態
    @State private var isMokugyoVersion: Bool = false
    
    @State private var engine: CHHapticEngine?
    
    // 圖片與音效
    @State private var currentFace: String = "face1"
    @State private var audioPlayer: AVAudioPlayer?
    
    // ★ 新增：讓使用者選擇音效
    @State private var selectedSoundEffect: String = "hit"
    
    // 手勢相關狀態
    @State private var isPressing: Bool = false
    @State private var pressDuration: Double = 0.0
    @State private var pressTimer: Timer?
    @State private var jitter: Double = 0.0
    
    // 動畫用變數：控制縮放與旋轉
    @State private var transformScale: CGFloat = 1.5
    @State private var transformRotation: Double = 0.0
    
    // 用來交替控制點按時的旋轉方向（正負）
    @State private var tapRotationSign: Double = 1.0
    
    // 連打計數相關
    @State private var comboCount: Int = 0
    @State private var lastTapTime: Date?
    @State private var comboJitter: CGSize = .zero
    
    // MARK: - Emoji 相關狀態
    @State private var showEmoji: Bool = false
    @State private var emojiText: String = ""
    @State private var emojiScale: CGFloat = 1.0
    @State private var emojiXOffset: CGFloat = 0.0
    @State private var emojiYOffset: CGFloat = 0.0
    
    @State private var comboResetTimer: Timer?
    @State private var comboBaseCount: Int? = nil
    
    // MARK: - AudioSession 設定
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession 設定失敗：\(error.localizedDescription)")
        }
    }
    
    // MARK: - 資料存取（七天統計）
    private func loadSevenDayCounts() -> [Int] {
        (try? JSONDecoder().decode([Int].self, from: sevenDayCountsData))
        ?? Array(repeating: 0, count: 7)
    }
    
    private func saveSevenDayCounts(_ counts: [Int]) {
        sevenDayCountsData = (try? JSONEncoder().encode(counts)) ?? Data()
    }
    
    // MARK: - 按壓計時與畫面更新
    private func startPressTimer() {
        pressDuration = 0.0
        pressTimer?.invalidate()
        pressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if isPressing {
                pressDuration += 0.05
                if pressDuration < 0.1 {
                    transformScale = CGFloat.random(in: 1.8...2.2)
                    transformRotation = tapRotationSign * Double.random(in: 20...40)
                } else if pressDuration < 0.2 {
                    transformScale = CGFloat.random(in: 1.4...2.6)
                    transformRotation = tapRotationSign * Double.random(in: 10...50)
                } else {
                    let progress = min((pressDuration - 0.2) / (3.0 - 0.2), 1.0)
                    transformScale = 2 - progress * (1.5 - 0.5)
                    jitter = Double.random(in: -10...10)
                    transformRotation = jitter
                }
            } else {
                pressTimer?.invalidate()
            }
        }
    }
    
    private func stopPressTimer() {
        pressTimer?.invalidate()
        pressTimer = nil
        jitter = 0
    }
    
    // MARK: - 震動與音效播放
    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }
    
    // ★ 根據是否為功德木魚版本來決定播放哪個音效檔案
    private func playSound() {
        let soundName: String = isMokugyoVersion ? "kokoko" : selectedSoundEffect
        if let soundURL = Bundle.main.url(forResource: soundName, withExtension: "wav") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.play()
            } catch {
                print("無法播放音效：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 音效與強震動連續播放（使用遞迴）
    private func scheduleSoundSequence(count: Int, interval: Double) {
        guard count > 0 else { return }
        playSound()
        let strongGenerator = UIImpactFeedbackGenerator(style: .heavy)
        strongGenerator.prepare()
        strongGenerator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            scheduleSoundSequence(count: count - 1, interval: interval)
        }
    }
    
    // MARK: - 更新統計數與圖片（每 50 次換圖）
    private func handleCountAndFaceChange() {
        currentSessionCount += 1
        todayCount += 1
        var counts = loadSevenDayCounts()
        counts[6] = todayCount
        saveSevenDayCounts(counts)
        if currentSessionCount > 0 && currentSessionCount % 50 == 0 {
            if isMokugyoVersion {
                currentFace = "mokugyo\(Int.random(in: 1...3))"
            } else {
                currentFace = "face\(Int.random(in: 1...18))"
            }
        }
    }
    
    // MARK: - 每日重置
    private func checkDateChange() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let todayKey = formatter.string(from: Date())
        let lastDateKey = UserDefaults.standard.string(forKey: "lastDateKey") ?? ""
        if todayKey != lastDateKey {
            var counts = loadSevenDayCounts()
            counts.removeFirst()
            counts.append(0)
            saveSevenDayCounts(counts)
            
            todayCount = 0
            todayComboCount = 0
            todayAppLaunchCount = 0
            UserDefaults.standard.set(todayKey, forKey: "lastDateKey")
        }
    }
    
    // MARK: - Emoji 觸發函式
    private func triggerEmoji(geo: GeometryProxy) {
        if isMokugyoVersion {
            // 功德木魚模式下以圖片呈現，隨機設定位置與初始縮放
            emojiXOffset = CGFloat.random(in: geo.size.width * 0.25 ... geo.size.width * 0.75)
            emojiYOffset = CGFloat.random(in: geo.size.height * 0.05 ... geo.size.height * 0.33)
            emojiScale = 0.1
            showEmoji = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                emojiScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showEmoji = false
                }
            }
        } else {
            let emojis = ["💢", "😠", "😡", "🤬", "😤", "💩", "🥹", "🥺", "😱", "😨", "😰", "🤮", "🤢"]
            emojiText = emojis.randomElement() ?? "💢"
            emojiXOffset = CGFloat.random(in: geo.size.width * 0.25 ... geo.size.width * 0.75)
            emojiYOffset = CGFloat.random(in: geo.size.height * 0.05 ... geo.size.height * 0.33)
            emojiScale = 0.1
            showEmoji = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                emojiScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showEmoji = false
                }
            }
        }
    }
    
    private func scheduleEmojiSequence(count: Int, interval: Double, geo: GeometryProxy) {
        guard count > 0 else { return }
        triggerEmoji(geo: geo)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            scheduleEmojiSequence(count: count - 1, interval: interval, geo: geo)
        }
    }
    
    // MARK: - 更新連打計數
    private func updateComboCount() {
        let now = Date()
        if let last = lastTapTime, now.timeIntervalSince(last) < 0.5 {
            comboCount += 1
        } else {
            comboCount = 1
            comboBaseCount = currentSessionCount % 50
        }
        
        if comboCount > todayComboCount {
            todayComboCount = comboCount
        }
        
        lastTapTime = now
        
        comboJitter = CGSize(width: Double.random(in: -10...10), height: Double.random(in: -10...10))
        withAnimation(.easeOut(duration: 0.5)) {
            comboJitter = .zero
        }
        
        comboResetTimer?.invalidate()
        comboResetTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) {
                comboCount = 0
                comboBaseCount = nil
            }
        }
    }
    
    let hasRequestedReviewKey = "hasRequestedReview"
    
    // MARK: - 主畫面
    var body: some View {
        NavigationStack {
            VStack {
                // 統計數據顯示
                HStack(spacing: 40) {
                    VStack {
                        Text("currentSessionCount")
                        Text("\(currentSessionCount)")
                            .font(.largeTitle)
                    }
                    VStack {
                        Text("todayCount")
                        Text("\(todayCount)")
                            .font(.largeTitle)
                    }
                    VStack {
                        Text("sevenDaysCount")
                        Text("\(loadSevenDayCounts().reduce(0, +))")
                            .font(.largeTitle)
                    }
                }
                .padding()
                
                Spacer()
                Text("tapToDefeat")
                
                Spacer()
                
                Text(String(format: NSLocalizedString("angerLevel", comment: ""), comboLevelText))
                    .font(.system(size: 16 + CGFloat(comboLevel) * 2, weight: comboLevelFontWeight))
                    .foregroundColor(.red)
                
                Spacer()
                
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        // 根據是否為功德木魚版本決定要呈現的圖片
                        Group {
                            if isMokugyoVersion {
                                // Mokugyo 模式只呈現木魚圖片，背景透明，並縮小 0.5 倍
                                Image(currentFace)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .background(Color.clear)
                            } else {
                                // 一般模式：依照自訂圖片或預設圖片顯示
                                (useCustomImage && customImage != nil ? Image(uiImage: customImage!) : Image(currentFace))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                        .scaledToFit()
                        // 若為木魚模式則將 transformScale 乘以 0.5
                        .scaleEffect(isMokugyoVersion ? transformScale * 0.5 : transformScale)
                        .rotationEffect(.degrees(transformRotation))
                        .colorMultiply(isPressing ? Color.black.opacity(0.6) : Color.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(
                            Rectangle()
                                .fill({
                                    if isPressing {
                                        // 若木魚模式按壓時不顯示紅色背景
                                        return isMokugyoVersion ? Color.clear : Color(red: 0.6, green: 0, blue: 0, opacity: 0.6)
                                    } else {
                                        if isMokugyoVersion {
                                            return Color.clear
                                        } else {
                                            let baseCount: Int = {
                                                if comboCount > 0, let base = comboBaseCount {
                                                    return base
                                                } else {
                                                    return 0
                                                }
                                            }()
                                            let comboExtra = comboCount > 1 ? (comboCount - 1) : 0
                                            let effectiveCount = min(baseCount + comboExtra, 50)
                                            let tapRatio = Double(effectiveCount) / 50.0
                                            let greenComponent = 0.6 * (1 - tapRatio)
                                            let blueComponent = 0.6 * (1 - tapRatio)
                                            return Color(red: 1.0, green: greenComponent, blue: blueComponent).opacity(0.8)
                                        }
                                    }
                                }())
                                .blendMode(.multiply)
                                .animation(.easeInOut(duration: 0.1), value: isPressing)
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isPressing {
                                        isPressing = true
                                        startPressTimer()
                                    }
                                }
                                .onEnded { _ in
                                    isPressing = false
                                    stopPressTimer()
                                    handleCountAndFaceChange()
                                    
                                    if pressDuration < 0.2 {
                                        triggerHaptic()
                                        playSound()
                                        triggerEmoji(geo: geo)
                                        updateComboCount()
                                        tapRotationSign = -tapRotationSign
                                    } else {
                                        let progress = min(pressDuration / 3.0, 1.0)
                                        let targetScale = 1.5 + progress * (4.0 - 1.5)
                                        let targetRotation = 15.0 + progress * (720.0 - 15.0)
                                        
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            transformScale = targetScale
                                            transformRotation = targetRotation
                                        }
                                        
                                        if pressDuration >= 3.0 {
                                            scheduleSoundSequence(count: 5, interval: 0.1)
                                            scheduleEmojiSequence(count: 5, interval: 0.1, geo: geo)
                                        } else if pressDuration >= 2.0 {
                                            scheduleSoundSequence(count: 3, interval: 0.1)
                                            scheduleEmojiSequence(count: 3, interval: 0.1, geo: geo)
                                        } else if pressDuration >= 1.0 {
                                            scheduleSoundSequence(count: 2, interval: 0.1)
                                            scheduleEmojiSequence(count: 2, interval: 0.1, geo: geo)
                                        } else {
                                            triggerHaptic()
                                            playSound()
                                        }
                                    }
                                }
                        )
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: transformScale)
                        .padding()
                        
                        if comboCount > 0 {
                            Text(String(format: NSLocalizedString("comboTapCount", comment: ""), comboCount))
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .offset(comboJitter)
                                .padding([.top, .trailing], 16)
                        }
                        
                        if showEmoji {
                            // 若為功德木魚模式，顯示 mokugyoemoji 圖片，否則呈現原有 emoji 文字
                            if isMokugyoVersion {
                                Image("mokugyoemoji")
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .scaleEffect(emojiScale)
                                    .position(x: emojiXOffset, y: emojiYOffset)
                            } else {
                                Text(emojiText)
                                    .font(.system(size: 50))
                                    .scaleEffect(emojiScale)
                                    .position(x: emojiXOffset, y: emojiYOffset)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
                
                // 原有功能按鈕：切換圖片模式與音效選擇
                HStack(spacing: 8) {
                    Button(action: {
                        if useCustomImage {
                            useCustomImage = false
                        } else {
                            customImage = nil
                            useCustomImage = true
                            showingImagePicker = true
                        }
                    }) {
                        Text(useCustomImage ?
                             NSLocalizedString("use_default_image", comment: "Switch to default image") :
                             NSLocalizedString("use_custom_image", comment: "Switch to custom image"))
                            .font(.footnote)
                            .padding(6)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Menu {
                        Button(NSLocalizedString("sound_effect_hit", comment: "Sound effect: hit (slap 1)")) {
                            selectedSoundEffect = "hit"
                        }
                        Button(NSLocalizedString("sound_effect_hit1", comment: "Sound effect: hit1 (slap 2)")) {
                            selectedSoundEffect = "hit1"
                        }
                        Button(NSLocalizedString("sound_effect_hit2", comment: "Sound effect: hit2 (slap 3)")) {
                            selectedSoundEffect = "hit2"
                        }
                        Button(NSLocalizedString("sound_effect_ough", comment: "Sound effect: ough (howl)")) {
                            selectedSoundEffect = "ough"
                        }
                        Button(NSLocalizedString("sound_effect_aaa", comment: "Sound effect: aaa (scream)")) {
                            selectedSoundEffect = "aaa"
                        }
                        Button(NSLocalizedString("sound_effect_kokoko", comment: "Sound effect: kokoko (wood fish)")) {
                            selectedSoundEffect = "kokoko"
                        }
                    } label: {
                        Text("\(NSLocalizedString("select_sound_effect", comment: "Select sound effect")): \(selectedSoundEffect)")
                            .font(.footnote)
                            .padding(6)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .padding(4)
                
                // ★ 新增按鈕：切換功德木魚版本
                Button(action: {
                    isMokugyoVersion.toggle()
                    if isMokugyoVersion {
                        // 切換到功德木魚模式時：強制改成 mokugyo 隨機圖片與 kokoko 音效，且關閉自訂圖片
                        currentFace = "mokugyo\(Int.random(in: 1...3))"
                        selectedSoundEffect = "kokoko"
                        useCustomImage = false
                    } else {
                        // 切換回一般模式，恢復預設圖片
                        currentFace = "face1"
                    }
                }) {
                    Text(isMokugyoVersion ?
                         NSLocalizedString("switch_back_normal", comment: "Switch back to normal version") :
                         NSLocalizedString("switch_mokugyo_version", comment: "Switch to Mokugyo version"))
                        .font(.footnote)
                        .padding(6)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }

                
                Text(String(format: NSLocalizedString("nextCharacter", comment: ""), 50 - (currentSessionCount % 50)))
                    .onAppear {
                        prepareHaptics()
                        checkDateChange()
                        configureAudioSession()
                    }
                
                VStack {
                    Button(NSLocalizedString("viewStatistics", comment: "")) {
                        requestReviewOnceIfNeeded()
                        showStatisticsView = true
                    }
                    .navigationDestination(isPresented: $showStatisticsView) {
                        StatisticsView(allDailyData: convertToDayCounts(loadSevenDayCounts()))
                    }
                }
                .padding()
                
            }
            
            Spacer()
            
            BannerAdView(adUnitID: "ca-app-pub-9275380963550837/6757899905")
                .frame(height: 50)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $customImage, isPresented: $showingImagePicker)
        }
    }
    
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
    
    func convertToDayCounts(_ sevenDayCounts: [Int]) -> [DayCount] {
        let calendar = Calendar.current
        let today = Date()
        
        let dayCounts = sevenDayCounts.enumerated().map { (index, count) -> DayCount in
            let offset = index - (sevenDayCounts.count - 1)
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            
            if offset == 0 {
                return DayCount(date: date,
                                count: count,
                                comboCount: todayComboCount,
                                appLaunchCount: todayAppLaunchCount)
            } else {
                return DayCount(date: date, count: count, comboCount: 0, appLaunchCount: 0)
            }
        }
        
        return dayCounts.sorted { $0.date < $1.date }
    }
    
    private func prepareHaptics() {
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("震動效果初始化錯誤: \(error.localizedDescription)")
        }
    }
    
    private var comboLevel: Int {
        if comboCount >= 60 {
            return 6
        } else if comboCount >= 50 {
            return 5
        } else {
            return comboCount / 10 + 1
        }
    }
    
    private var comboLevelFontWeight: Font.Weight {
        switch comboLevel {
        case 1:
            return .regular
        case 2:
            return .medium
        case 3:
            return .semibold
        case 4:
            return .bold
        case 5:
            return .heavy
        default:
            return .black
        }
    }
    
    private var comboLevelText: String {
        if comboCount >= 60 {
            return NSLocalizedString("comboLevel.proMaxAnger", comment: "")
        } else if comboCount >= 50 {
            return NSLocalizedString("comboLevel.maxAnger", comment: "")
        } else {
            let level = comboCount / 10 + 1
            switch level {
            case 1...2:
                return String(format: NSLocalizedString("comboLevel.calm", comment: ""), level)
            case 3...4:
                return String(format: NSLocalizedString("comboLevel.moderateAnger", comment: ""), level)
            case 5...6:
                return String(format: NSLocalizedString("comboLevel.severeAnger", comment: ""), level)
            default:
                return "\(level)"
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
