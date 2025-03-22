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
                    // 點按效果：固定 1.5 倍與 30°（依 tapRotationSign 交替）
                    transformScale = 2
                    transformRotation = tapRotationSign * 30.0
                } else if pressDuration < 0.2 {
                    // 介於 0.1 ~ 0.2 秒之間：保持點按效果
                    transformScale = 2
                    transformRotation = tapRotationSign * 30.0
                } else {
                    // 長按效果：開始依 (pressDuration - 0.2) 漸變
                    let progress = min((pressDuration - 0.2) / (3.0 - 0.2), 1.0)
                    // 逐漸縮小：從 1.5 倍縮放到 0.5 倍
                    transformScale = 2 - progress * (1.5 - 0.5)
                    // 加入隨機 jitter，範圍 ±5°
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
        // 強震動反饋：使用 heavy 風格
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
                
                // 在 face 的右上方顯示連打數
                if comboCount > 0 {
                    Text("イライラ連打：\(comboCount) ")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .offset(comboJitter)
                        .padding([.top, .trailing], 16)
                }
                
                // 手勢區域：使用 DragGesture(minimumDistance: 0) 捕捉點按與長按
                Image(currentFace)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaledToFit()
                    .scaleEffect(transformScale)
                    .rotationEffect(.degrees(transformRotation))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                
                                if pressDuration < 0.2 {
                                    // 點按：播放一次音效
                                    triggerHaptic() // 加入震動
                                    playSound()
                                    transformScale = 1.5
                                    transformRotation = 0.0
                                    // 更新連打計數
                                    updateComboCount()
                                    // 交替旋轉方向
                                    tapRotationSign = -tapRotationSign
                                } else {
                                    // 長按：放開後根據按壓時長觸發動畫效果
                                    let progress = min(pressDuration / 3.0, 1.0)
                                    // 從 1.5 倍漸變至 4 倍
                                    let targetScale = 1.5 + progress * (4.0 - 1.5)
                                    // 從 15° 漸變至 720°（基礎從 15° 起）
                                    let targetRotation = 15.0 + progress * (720.0 - 15.0)
                                    
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        transformScale = targetScale
                                        transformRotation = targetRotation
                                    }
                                    
                                    // 根據按壓時間播放音效與強震動連續播放（間隔 0.1 秒）
                                    if pressDuration >= 3.0 {
                                        scheduleSoundSequence(count: 5, interval: 0.1)
                                    } else if pressDuration >= 2.0 {
                                        scheduleSoundSequence(count: 3, interval: 0.1)
                                    } else if pressDuration >= 1.0 {
                                        scheduleSoundSequence(count: 2, interval: 0.1)
                                    } else {
                                        triggerHaptic()
                                        playSound()
                                    }
                                    
                                    // 放開後稍後恢復到原狀
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            transformScale = 1.5
                                            transformRotation = 0.0
                                        }
                                    }
                                }
                                
                                // 更新計數與圖片
                                handleCountAndFaceChange()
                            }
                    )
                    .animation(.spring(response: 0.2, dampingFraction: 0.5), value: transformScale)
                    .padding()
                
                
                Spacer()
                
                Text("あと \(50 - (currentSessionCount % 50)) タップで新しい演出が…？")
                    .onAppear {
                        // 把所有需要在出現時執行的動作放在同一個 closure
                        prepareHaptics()
                        checkDateChange()
                        configureAudioSession()
                        
                    }
                
                NavigationLink("イライラ統計をチェックする →", destination: StatisticsView(sevenDayCounts: loadSevenDayCounts()))
                    .padding()
            }
            
            Spacer() // 讓廣告顯示在底部

            BannerAdView(adUnitID: "ca-app-pub-9275380963550837/6757899905") // 測試 AdMob ID
                .frame(height: 50) // 設定 banner 高度
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
    
    // MARK: - 更新連打計數
     private func updateComboCount() {
         let now = Date()
         if let last = lastTapTime, now.timeIntervalSince(last) < 0.5 {
             comboCount += 1
         } else {
             comboCount = 1
         }
         lastTapTime = now
         
         // 產生隨機抖動偏移，再以動畫回復到原位
         comboJitter = CGSize(width: Double.random(in: -10...10), height: Double.random(in: -10...10))
         withAnimation(.easeOut(duration: 0.5)) {
             comboJitter = .zero
         }
     }
}



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
