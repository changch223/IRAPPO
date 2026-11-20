import AVFoundation
import AudioToolbox
import QuartzCore

/// 打擊音效：AVAudioEngine + 一組 AVAudioPlayerNode，快速連點時聲音可疊加、盡量不被截斷。
///
/// 執行緒：session 設定、引擎建立、節點、音檔解碼、啟動 / 重啟、播放，全部只在專用的序列佇列 `queue` 上做。
/// 呼叫端（主執行緒）只負責丟進佇列，不會被音訊服務卡住。
final class AudioEngine {
    static let shared = AudioEngine()

    // MARK: - 可調常數
    private enum Config {
        static let poolSize = 12
        static let allSounds = ["hit", "kokoko",
                                "clang", "whoosh", "ping", "boom", "chime",
                                "slipper", "hammer", "shatter", "bolt", "kb", "bubble"]
        static let defaultSound = "hit"
        static let pitchCentsPerCombo: Float = 12   // 每一連擊升高的音分
        static let maxPitchCents: Float = 600       // 音高上限（半個八度）
        static let maxPitchCombo = 50
        static let nodeVolume: Float = 0.5          // 每個 node 的 headroom，避免多聲重疊爆音
        static let useLimiter = true                // mixer 後接 PeakLimiter
        /// 引擎還沒準備好時，最近一次播放要求在這個秒數內還新鮮才補播，否則丟掉
        static let pendingFreshness: TimeInterval = 0.15
    }

    private struct PlayRequest {
        let name: String
        let combo: Int
        let requestedAt: CFTimeInterval
    }

    private let queue = DispatchQueue(label: "irappo.audio", qos: .userInteractive)

    // 聲音開關：主執行緒寫、play() 讀，用鎖保護
    private let enabledLock = NSLock()
    private var _isEnabled = true
    var isEnabled: Bool {
        get { enabledLock.lock(); defer { enabledLock.unlock() }; return _isEnabled }
        set { enabledLock.lock(); _isEnabled = newValue; enabledLock.unlock() }
    }

    // ---- 以下狀態只在 `queue` 上存取 ----
    private var engine: AVAudioEngine?
    private var nodes: [AVAudioPlayerNode] = []
    private var pitchUnits: [AVAudioUnitTimePitch] = []
    /// 每個 node 目前這段聲音預計播完的時間（CACurrentMediaTime）
    private var busyUntil: [CFTimeInterval] = []
    private var startedAt: [CFTimeInterval] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var failedNames: Set<String> = []
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private var observers: [NSObjectProtocol] = []
    private var pending: PlayRequest?

    /// iOS 模擬器（目前的 Xcode 26 / macOS 26 環境）上，只要碰到 AVAudioEngine 的輸出節點（`mainMixerNode`）
    /// 就會卡在 AURemoteIO 的 RPC，約 14 秒後 AudioToolbox 直接 abort 整個 app（連最小的空引擎都一樣，
    /// 單元測試 host 也是同樣的閃退）。AVAudioPlayer 在模擬器上正常。
    /// 所以模擬器改用 AVAudioPlayer 小池子（沒有音高變化），真機一律走 AVAudioEngine。
    #if targetEnvironment(simulator)
    private static let useEngine = false
    #else
    private static let useEngine = true
    #endif
    private var simulatorPlayers: [String: [AVAudioPlayer]] = [:]
    private static let simulatorPoolPerSound = 4

    private init() {}

    // MARK: - 公開（主執行緒呼叫，非同步，不會阻塞）

    /// 立刻開始設定：session（.ambient，跟隨實體靜音鍵）→ 建立引擎 → 先解碼 priority（目前武器的打擊聲、木魚聲）→ 其餘音檔。
    func prepare(priority: [String] = []) {
        guard !AppEnvironment.isRunningTests else { return }
        queue.async { [self] in
            configureSession()
            if Self.useEngine, engine == nil { buildEngine() }
            startEngineIfNeeded()
            flushPending()
        }
        guard Self.useEngine else {
            // 模擬器：先暖好目前武器與木魚聲的 AVAudioPlayer
            queue.async { [self] in
                for name in priority { _ = simulatorPlayer(for: name) }
            }
            return
        }
        // 解碼分成小段，穿插在播放要求之間
        for name in priority {
            queue.async { [self] in _ = ensureBuffer(name) }
        }
        for name in Config.allSounds {
            queue.async { [self] in _ = ensureBuffer(name) }
        }
    }

    func start() {
        guard !AppEnvironment.isRunningTests else { return }
        queue.async { [self] in
            startEngineIfNeeded()
            flushPending()
        }
    }

    /// 播放一個音效，音高隨連擊升高（有上限）。
    func play(_ name: String, combo: Int) {
        guard !AppEnvironment.isRunningTests, isEnabled else { return }
        let request = PlayRequest(name: name, combo: combo, requestedAt: CACurrentMediaTime())
        queue.async { [self] in handle(request) }
    }

    // MARK: - queue 內部

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession 設定失敗：\(error.localizedDescription)")
        }
    }

    private func buildEngine() {
        let engine = AVAudioEngine()
        for _ in 0..<Config.poolSize {
            let node = AVAudioPlayerNode()
            let pitch = AVAudioUnitTimePitch()
            node.volume = Config.nodeVolume
            engine.attach(node)
            engine.attach(pitch)
            engine.connect(node, to: pitch, format: format)
            engine.connect(pitch, to: engine.mainMixerNode, format: format)
            nodes.append(node)
            pitchUnits.append(pitch)
        }
        busyUntil = Array(repeating: 0, count: Config.poolSize)
        startedAt = Array(repeating: 0, count: Config.poolSize)

        if Config.useLimiter {
            let desc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_PeakLimiter,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0, componentFlagsMask: 0)
            let limiter = AVAudioUnitEffect(audioComponentDescription: desc)
            engine.attach(limiter)
            engine.connect(engine.mainMixerNode, to: limiter, format: nil)
            engine.connect(limiter, to: engine.outputNode, format: nil)
        }
        engine.prepare()
        self.engine = engine

        let center = NotificationCenter.default
        // 通知可能在任何執行緒送出：一律丟回 queue 處理
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.queue.async {
                self?.startEngineIfNeeded()
                self?.flushPending()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            self?.queue.async {
                self?.configureSession()
                self?.startEngineIfNeeded()
                self?.flushPending()
            }
        })
    }

    private func startEngineIfNeeded() {
        guard let engine, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("AVAudioEngine 啟動失敗：\(error.localizedDescription)")
        }
    }

    private func handle(_ request: PlayRequest) {
        guard Self.useEngine else {
            if CACurrentMediaTime() - request.requestedAt < Config.pendingFreshness {
                simulatorPlayer(for: request.name)?.play()
            }
            return
        }
        guard let engine, engine.isRunning else {
            // 引擎還沒好（或路由切換中）：只留最近一次，等好了再補播
            pending = request
            return
        }
        guard CACurrentMediaTime() - request.requestedAt < Config.pendingFreshness else { return }
        perform(request, on: engine)
    }

    private func flushPending() {
        guard let request = pending, let engine, engine.isRunning else { return }
        pending = nil
        guard CACurrentMediaTime() - request.requestedAt < Config.pendingFreshness else { return }
        perform(request, on: engine)
    }

    private func perform(_ request: PlayRequest, on engine: AVAudioEngine) {
        guard let buffer = buffer(for: request.name) else { return }
        let now = CACurrentMediaTime()
        let index = pickNode(now: now)
        let node = nodes[index]
        let steps = Float(min(max(request.combo, 0), Config.maxPitchCombo))
        pitchUnits[index].pitch = min(steps * Config.pitchCentsPerCombo, Config.maxPitchCents)

        startedAt[index] = now
        // 音高升高會讓播放變短，用原長度估計即可（偏保守）
        busyUntil[index] = now + Double(buffer.frameLength) / buffer.format.sampleRate

        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying, engine.isRunning { node.play() }
    }

    /// 先挑已播完（閒置）的 node，全忙時挑最早開始的那個。
    private func pickNode(now: CFTimeInterval) -> Int {
        var oldest = 0
        for i in 0..<nodes.count {
            if busyUntil[i] <= now { return i }
            if startedAt[i] < startedAt[oldest] { oldest = i }
        }
        return oldest
    }

    /// 模擬器用：每個音效一小組 AVAudioPlayer，挑閒置的從頭播；都在忙就重播第一個。
    private func simulatorPlayer(for name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: Config.defaultSound, withExtension: "wav") else { return nil }
        var pool = simulatorPlayers[name] ?? []
        if let idle = pool.first(where: { !$0.isPlaying }) {
            idle.currentTime = 0
            return idle
        }
        if pool.count < Self.simulatorPoolPerSound, let p = try? AVAudioPlayer(contentsOf: url) {
            p.prepareToPlay()
            pool.append(p)
            simulatorPlayers[name] = pool
            return p
        }
        let first = pool.first
        first?.currentTime = 0
        return first
    }

    // MARK: - 音檔載入（統一轉成 44.1kHz 立體聲，才能接到同一組 node）
    /// 找不到或載入失敗的音效會被記住，退回預設音效，不會每下重讀硬碟。
    private func buffer(for name: String) -> AVAudioPCMBuffer? {
        if let b = ensureBuffer(name) { return b }
        if name != Config.defaultSound { return buffer(for: Config.defaultSound) }
        return nil
    }

    @discardableResult
    private func ensureBuffer(_ name: String) -> AVAudioPCMBuffer? {
        if let b = buffers[name] { return b }
        if failedNames.contains(name) { return nil }
        if let b = loadBuffer(named: name) {
            buffers[name] = b
            return b
        }
        failedNames.insert(name)
        return nil
    }

    private func loadBuffer(named name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            let srcFormat = file.processingFormat
            guard let src = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: src)
            if srcFormat == format { return src }

            guard let converter = AVAudioConverter(from: srcFormat, to: format) else { return nil }
            let ratio = format.sampleRate / srcFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(src.frameLength) * ratio) + 1024
            guard let dst = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
            var consumed = false
            var error: NSError?
            converter.convert(to: dst, error: &error) { _, status in
                if consumed {
                    status.pointee = .endOfStream
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return src
            }
            if let error { throw error }
            return dst
        } catch {
            print("無法載入音效 \(name)：\(error.localizedDescription)")
            return nil
        }
    }
}
