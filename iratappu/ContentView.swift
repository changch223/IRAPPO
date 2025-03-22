import SwiftUI
import CoreHaptics
import AVFoundation
import Combine
import GoogleMobileAds

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    // 統計與計數
    @State private var currentSessionCount = 0
    @AppStorage("todayCount") private var todayCount = 0
    @AppStorage("sevenDayCountsData") private var sevenDayCountsData = Data()
    @State private var engine: CHHapticEngine?
    
    // 圖片與音效
    @State private var currentFace: String = "face1"
    @State private var audioPlayer: AVAudioPlayer?
    
    // 手勢相關狀態
    @State private var isPressing: Bool = false
    @State private var pressDuration: Double = 0.0   // 單位：秒
    @State private var pressTimer: Timer?
    @State private var jitter: Double = 0.0          // 隨機抖動值
    
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
                    // 點按效果：隨機浮動的縮放與旋轉
                    transformScale = CGFloat.random(in: 1.8...2.2)
                    transformRotation = tapRotationSign * Double.random(in: 20...40)
                } else if pressDuration < 0.2 {
                    // 介於 0.1 ~ 0.2 秒之間，保持隨機效果
                    transformScale = CGFloat.random(in: 1.4...2.6)
                    transformRotation = tapRotationSign * Double.random(in: 10...50)
                } else {
                    // 長按效果：開始依 (pressDuration - 0.2) 漸變
                    let progress = min((pressDuration - 0.2) / (3.0 - 0.2), 1.0)
                    // 逐漸縮小：從 1.5 倍縮放到 0.5 倍
                    transformScale = 2 - progress * (1.5 - 0.5)
                    // 加入隨機 jitter，範圍 ±10°
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
    
    // MARK: - 震動與音效播放
    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }
    
    private func playSound() {
        if let soundURL = Bundle.main.url(forResource: "hit", withExtension: "wav") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.play()
            } catch {
                print("無法播放音效：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 更新統計數與圖片（每 50 次換圖）
    private func handleCountAndFaceChange() {
        // 先更新 currentSessionCount 與其他統計數
        currentSessionCount += 1
        todayCount += 1
        var counts = loadSevenDayCounts()
        counts[6] = todayCount
        saveSevenDayCounts(counts)
        if currentSessionCount > 0 && currentSessionCount % 50 == 0 {
            currentFace = "face\(Int.random(in: 1...18))"
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
            UserDefaults.standard.set(todayKey, forKey: "lastDateKey")
        }
    }
    
    // MARK: - Emoji 觸發函式
    private func triggerEmoji(geo: GeometryProxy) {
        let emojis = ["💢", "😠", "😡", "🤬", "😤", "💩", "🥹", "🥺", "😱", "😨", "😰", "🤮", "🤢"]
        emojiText = emojis.randomElement() ?? "💢"
        // 隨機位置：限制在圖片上方區域
        emojiXOffset = CGFloat.random(in: geo.size.width * 0.25 ... geo.size.width * 0.75)
        emojiYOffset = CGFloat.random(in: geo.size.height * 0.05 ... geo.size.height * 0.33)
        emojiScale = 0.1
        showEmoji = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
            emojiScale = 1.0
        }
        // 1秒後隱藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showEmoji = false
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
            // 以更新後的 currentSessionCount 當作連打起始基底
            comboBaseCount = currentSessionCount % 50
        }
        lastTapTime = now
        
        // 產生隨機抖動偏移，再以動畫回復到原位
        comboJitter = CGSize(width: Double.random(in: -10...10), height: Double.random(in: -10...10))
        withAnimation(.easeOut(duration: 0.5)) {
            comboJitter = .zero
        }
        // 取消先前的計時器（如果存在）
        comboResetTimer?.invalidate()
        // 重新設定 3 秒後重置 comboCount 的計時器
        comboResetTimer?.invalidate()
        comboResetTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) {
                comboCount = 0
                comboBaseCount = nil  // 清除連打基底
            }
        }
    }
    
    // MARK: - 主畫面
    var body: some View {
        NavigationStack {
            VStack {
                // 統計數據顯示
                HStack(spacing: 40) {
                    VStack {
                        Text("現在💢度")
                        Text("\(currentSessionCount)")
                            .font(.largeTitle)
                    }
                    VStack {
                        Text("今日💢度")
                        Text("\(todayCount)")
                            .font(.largeTitle)
                    }
                    VStack {
                        Text("最近七日間")
                        Text("\(loadSevenDayCounts().reduce(0, +))")
                            .font(.largeTitle)
                    }
                }
                .padding()
                
                Spacer()
                Text("イラっとしたら、タップでストレス解消！")
                
                Spacer()
                
                Text("イラっ返し度：\(comboLevelText)")
                    .font(.system(size: 16 + CGFloat(comboLevel) * 2, weight: comboLevelFontWeight))
                    .foregroundColor(.red)
                
                Spacer()
                
                
                
                // 使用 GeometryReader 包裝圖片，方便計算位置與隨機 emoji 出現位置
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        Image(currentFace)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaledToFit()
                            .scaleEffect(transformScale)
                            .rotationEffect(.degrees(transformRotation))
                            .colorMultiply(isPressing ? Color.black.opacity(0.6) : Color.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                Rectangle()
                                    .fill({
                                        if isPressing {
                                            return Color(red: 0.6, green: 0, blue: 0, opacity: 0.6)
                                        } else {
                                            let baseCount: Int = {
                                                if comboCount > 0, let base = comboBaseCount {
                                                    return base
                                                } else {
                                                    // 非連打狀態回到原始淡紅色（有效值 0）
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
                                        
                                        // 先更新統計數（currentSessionCount、todayCount 等）
                                        handleCountAndFaceChange()
                                        
                                        if pressDuration < 0.2 {
                                            // 點按：觸發單次 emoji、音效與震動
                                            triggerHaptic()
                                            playSound()
                                            triggerEmoji(geo: geo)
                                            // 使用已更新的 currentSessionCount 來記錄連打基底
                                            updateComboCount()
                                            tapRotationSign = -tapRotationSign
                                        } else {
                                            // 長按效果：根據按壓時長觸發不同動畫
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
                                Text("イラっ返し連打数：\(comboCount)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(8)
                                    .offset(comboJitter)
                                    .padding([.top, .trailing], 16)
                            }
                        
                        if showEmoji {
                            Text(emojiText)
                                .font(.system(size: 50))
                                .scaleEffect(emojiScale)
                                .position(x: emojiXOffset, y: emojiYOffset)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
                
                Text("あと \(50 - (currentSessionCount % 50)) タップで、新しい人が登場…？")
                    .onAppear {
                        prepareHaptics()
                        checkDateChange()
                        configureAudioSession()
                    }
                
                NavigationLink("イライラ統計をチェックする →", destination: StatisticsView(sevenDayCounts: loadSevenDayCounts()))
                    .padding()
            }
            
            Spacer() // 讓廣告顯示在底部
            
            BannerAdView(adUnitID: "ca-app-pub-9275380963550837/6757899905")
                .frame(height: 50)
        }
    }
    
    // MARK: - 震動引擎初始化
    private func prepareHaptics() {
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("震動效果初始化錯誤: \(error.localizedDescription)")
        }
    }
    
    // 計算數值等級（數字形式）
    private var comboLevel: Int {
        if comboCount >= 60 {
            return 6
        } else if comboCount >= 50 {
            return 5
        } else {
            return comboCount / 10 + 1
        }
    }
    // 根據等級決定字體粗細
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
    // 依據 comboCount 決定等級顯示文字
    private var comboLevelText: String {
        if comboCount >= 50 {
            if comboCount >= 60 {
                return "ProMax"
            }
            return "Max"
        } else {
            return "\(comboCount / 10 + 1)"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
