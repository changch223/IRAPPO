import CoreHaptics
import UIKit

/// 打擊震動：CHHapticEngine transient 事件，強度/銳利度隨力道。裝置不支援時退回系統 impact。
final class HapticsEngine {
    static let shared = HapticsEngine()

    // MARK: - 可調常數
    private enum Config {
        static let baseIntensity: Float = 0.35
        static let intensityPerPower: Float = 0.30
        static let baseSharpness: Float = 0.40
        static let sharpnessPerPower: Float = 0.25
        static let tickIntensity: Float = 0.25
        static let tickSharpness: Float = 0.3
        // 鐵鎚：短而銳利
        static let sharpBase: Float = 0.7
        static let sharpSharpness: Float = 1.0
        // 泡泡紙：輕而軟
        static let softIntensity: Float = 0.25
        static let softSharpness: Float = 0.1
        // 雷電：重擊 + 餘震
        static let rumbleTailIntensity: Float = 0.4
        static let rumbleTailDuration: TimeInterval = 0.18
    }

    // 引擎建立與啟動可能卡在觸覺服務：全部放在專用序列佇列；就緒前的震動用 UIImpactFeedbackGenerator 頂著。
    private let queue = DispatchQueue(label: "irappo.haptics", qos: .userInteractive)
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let fallback = UIImpactFeedbackGenerator(style: .heavy)
    private let readyLock = NSLock()
    private var _isReady = false
    private var isReady: Bool {
        get { readyLock.lock(); defer { readyLock.unlock() }; return _isReady }
        set { readyLock.lock(); _isReady = newValue; readyLock.unlock() }
    }
    /// 只在 queue 上存取
    private var engine: CHHapticEngine?

    private init() {}

    /// 啟動時就呼叫即可（非同步，不阻塞主執行緒）。
    func prepare() {
        guard !AppEnvironment.isRunningTests else { return }
        DispatchQueue.main.async { [fallback] in fallback.prepare() }
        guard supportsHaptics else { return }
        queue.async { [self] in
            if engine == nil {
                do {
                    let e = try CHHapticEngine()
                    e.isAutoShutdownEnabled = true
                    e.resetHandler = { [weak self] in
                        // 服務重啟後引擎要重新啟動
                        self?.queue.async { try? self?.engine?.start() }
                    }
                    engine = e
                } catch {
                    print("震動效果初始化錯誤: \(error.localizedDescription)")
                    return
                }
            }
            do {
                try engine?.start()
                isReady = true
            } catch {
                isReady = false
            }
        }
    }

    /// power：拳 1、蓄力更強。style 依武器：鐵鎚短而銳利、泡泡紙輕而軟、雷電一下重擊加一段餘震。
    func play(power: CGFloat, style: HapticStyle = .scaled) {
        let p = Float(power)
        switch style {
        case .scaled:
            let intensity = min(1, Config.baseIntensity + Config.intensityPerPower * p)
            let sharpness = min(1, Config.baseSharpness + Config.sharpnessPerPower * p)
            play(intensity: intensity, sharpness: sharpness)
        case .sharp:
            play(intensity: min(1, Config.sharpBase + 0.15 * p), sharpness: Config.sharpSharpness)
        case .soft:
            play(intensity: Config.softIntensity, sharpness: Config.softSharpness)
        case .rumble:
            let hit = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ], relativeTime: 0)
            let tail = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Config.rumbleTailIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ], relativeTime: 0.03, duration: Config.rumbleTailDuration)
            play(events: [hit, tail], fallbackIntensity: 1.0)
        }
    }

    /// 蓄力開始的輕輕一下
    func playLightTick() {
        play(intensity: Config.tickIntensity, sharpness: Config.tickSharpness)
    }

    private func play(intensity: Float, sharpness: Float) {
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: 0)
        play(events: [event], fallbackIntensity: intensity)
    }

    private func play(events: [CHHapticEvent], fallbackIntensity intensity: Float) {
        guard !AppEnvironment.isRunningTests else { return }
        let fallbackStrength = CGFloat(min(1, 0.3 + intensity * 0.7))
        // 引擎還沒好（或不支援）：直接用系統 impact（呼叫端在主執行緒）
        guard supportsHaptics, isReady else {
            fallbackOnMain(fallbackStrength)
            return
        }
        queue.async { [self] in
            guard let engine else {
                fallbackOnMain(fallbackStrength)
                return
            }
            do {
                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try engine.start()          // 已在跑時為 no-op；被系統停掉時會重新啟動
                try player.start(atTime: CHHapticTimeImmediate)
            } catch {
                // 靜默退回
                fallbackOnMain(fallbackStrength)
            }
        }
    }

    private func fallbackOnMain(_ strength: CGFloat) {
        if Thread.isMainThread {
            fallback.impactOccurred(intensity: strength)
        } else {
            DispatchQueue.main.async { [fallback] in fallback.impactOccurred(intensity: strength) }
        }
    }
}
