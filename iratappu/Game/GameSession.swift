import SwiftUI

struct FaceTransform: Equatable {
    var rotation: Double = 0
    var scale: CGFloat = 1
    var dx: CGFloat = 0
}

struct Ghost: Identifiable {
    let id = UUID()
    let image: Image
    let sign: Double
}

struct Callout: Equatable, Identifiable {
    let id: Int
    let text: String
}

enum SessionConfig {
    static let tickInterval: TimeInterval = 0.05
    static let koTextDuration: TimeInterval = 0.65
    static let bossKoTextDuration: TimeInterval = 0.9
    static let ghostDuration: TimeInterval = 0.9
    static let tapFaceReset: TimeInterval = 0.09
    static let swipeFaceReset: TimeInterval = 0.17
    static let swipeFaceShift: CGFloat = 0.2        // 相對打擊區寬
    static let koImpacts = 3
    static let bossKoImpacts = 6
    static let koImpactPower: CGFloat = 1.8
    static let bossKoImpactPower: CGFloat = 2.4
    static let koHapticPower: CGFloat = 2.2
    static let bossKoHapticPower: CGFloat = 3.0
    static let faceFraction: CGFloat = 0.45         // 角色框佔舞台寬 / 高（取小者）的比例（圖片已裁掉透明邊）；約為改版前可見大小的 1.5 倍
    static let faceCenterY: CGFloat = 0.55          // 角色中心在舞台高度的偏好位置（舞台太矮時由 StageGeometry 往下調）
    static let weakSpotFaceWidth: CGFloat = 0.8     // 弱點圓心可出現的範圍：角色框寬的這個比例（再往內縮一個半徑）
    static let weakSpotFaceHeight: CGFloat = 0.9
    static let weakSpotRadius: CGFloat = 0.15       // 弱點半徑 = 角色框 × 這個比例
    static let weakSpotMinRadius: CGFloat = 22      // 直徑至少 44pt（點擊下限）
    static let bossFaceScale: CGFloat = 1.14
    static let mokugyoFaceScale: CGFloat = 0.8
    static let mokugyoTextColor = Color(red: 0x8A / 255, green: 0x52 / 255, blue: 0)
}

/// 把 GameEngine 的事件接到畫面、特效、聲音、震動與情境提示。
final class GameSession: ObservableObject {
    // MARK: 給畫面讀的狀態
    @Published private(set) var mode: GameMode = .rage {
        didSet { if mode != oldValue { settings.mode = mode } }
    }
    @Published private(set) var enemy: Enemy
    @Published private(set) var combo = 0
    @Published private(set) var multiplier = 1.0
    @Published private(set) var merit = 0
    @Published private(set) var phase: GameEngine.Phase = .idle
    @Published private(set) var isCharging = false
    @Published private(set) var weakSpot: WeakSpot?
    @Published private(set) var coolingActive = false
    @Published private(set) var faceTransform = FaceTransform()
    @Published private(set) var faceID = 0
    @Published private(set) var ghosts: [Ghost] = []
    @Published private(set) var koText: Callout?
    @Published private(set) var pressPoint: CGPoint = .zero
    @Published private(set) var unlockedCount: Int
    @Published var result: RunSummary?

    // 自訂照片（可當作對手）
    @Published var customImage: UIImage? {
        didSet {
            // 照片縮圖、編碼、寫檔都在背景序列佇列（順序一致，不卡主執行緒）；只存在本機
            let image = customImage
            let settings = settings
            photoQueue.async { settings.savePhoto(image) }
            updateCustomCrop()
        }
    }
    /// 自訂照片裁掉透明邊的版本（背景處理；照片關掉就釋放）
    @Published private(set) var customCropped: UIImage?
    @Published var useCustomImage = false {
        didSet {
            guard useCustomImage != oldValue else { return }
            settings.useCustomPhoto = useCustomImage
            if !useCustomImage { customImage = nil }     // 關掉就一併刪除檔案
        }
    }
    /// 下一輪的起始角色（圖鑑選的）
    @Published private(set) var startingCharacter = 0
    @Published private(set) var mokugyoFace = 1

    // MARK: 由 ContentView 同步進來
    var reduceMotion = false {
        didSet { weaponFX.reduceMotion = reduceMotion }
    }
    /// 統計：每個手勢（點 / 滑 / 蓄力放開）算一次，蓄力爆發的每一下不重複算
    /// 一輪結束、結算頁出現之前的關卡（外層可以在這裡先出全螢幕廣告，完成後呼叫 show）
    var resultGate: ((_ show: @escaping () -> Void) -> Void)?
    var onGesture: (() -> Void)?
    /// 每次連擊數變動（記最高連擊用）
    var onCombo: ((_ combo: Int) -> Void)?

    let fx = FXModel()
    let decals = DecalModel()
    let coach = CoachManager()
    let engine: GameEngine
    let weaponProgress = WeaponProgress()
    let weaponFX: WeaponFX
    let settings: SettingsStore

    /// 目前武器（只影響特效、聲音、震動，不影響任何數值）
    @Published private(set) var weapon: Weapon = Weapons.weapon(.fist)
    /// 這一輪新解鎖的武器（結算頁「新紀錄」用）
    @Published private(set) var runWeapons: [Weapon] = []
    /// 白閃（0...1），畫面層疊上去並淡出
    @Published private(set) var flash: Double = 0

    private(set) var pressBeganUptime: TimeInterval = 0
    private var tickTimer: Timer?
    private var burstToken = 0
    private var koCounter = 0
    private var finishToken = 0
    private let photoQueue = DispatchQueue(label: "irappo.photo", qos: .utility)
    private var decalClearWork: DispatchWorkItem?
    private var tiltSign = 1.0
    private var faceReset: DispatchWorkItem?
    private var started = false
    #if DEBUG
    /// 截圖用：停掉 tick，畫面停在現在的狀態
    var debugFrozen = false
    #endif
    private let defaults = UserDefaults.standard

    var stage: CGSize {
        get { engine.stage }
        set {
            engine.stage = newValue
            weaponFX.stage = newValue
        }
    }

    /// 舞台區（hp 列和下方按鈕之間）在畫面座標的位置。打擊區是整個螢幕，角色放在舞台區裡。
    private(set) var stageRect: CGRect = .zero
    /// 角色框邊長（不含魔王的 1.14 倍）
    private(set) var faceSide: CGFloat = 0
    private(set) var faceCenter: CGPoint = .zero

    /// 由畫面層回報版面（角色大小與位置由 StageGeometry 算好）。弱點範圍與特效中心都跟著角色。
    func setLayout(screen: CGSize, geometry g: StageGeometry) {
        guard screen.width > 0, g.region.width > 0, g.region.height > 0 else { return }
        stageRect = g.region
        faceSide = g.faceSide
        faceCenter = g.faceCenter
        stage = screen
        // 弱點：半徑跟角色框走；圓心範圍往內縮一個半徑，整個圓都在臉上
        let r = max(SessionConfig.weakSpotMinRadius, faceSide * SessionConfig.weakSpotRadius)
        let w = max(0, faceSide * SessionConfig.weakSpotFaceWidth - 2 * r)
        let h = max(0, faceSide * SessionConfig.weakSpotFaceHeight - 2 * r)
        engine.weakSpotRadius = Double(r)
        engine.weakSpotArea = CGRect(x: faceCenter.x - w / 2, y: faceCenter.y - h / 2, width: w, height: h)
        weaponFX.faceCenter = faceCenter
    }

    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        let unlocked = max(GameConfig.initialUnlocked, UserDefaults.standard.integer(forKey: "unlockedCount"))
        engine = GameEngine(unlockedCount: unlocked)
        engine.bestCombo = UserDefaults.standard.integer(forKey: "bestCombo")
        engine.bestRun = UserDefaults.standard.integer(forKey: "bestRunKO")
        enemy = engine.enemy
        unlockedCount = engine.unlockedCount
        // 還原設定（init 內賦值不會觸發 didSet）
        mode = settings.mode
        startingCharacter = min(settings.startingCharacter, engine.unlockedCount - 1)
        if settings.useCustomPhoto {
            if let photo = settings.loadPhoto() {
                customImage = photo
                useCustomImage = true
            } else {
                settings.useCustomPhoto = false          // 檔案不見了
            }
        }
        weaponFX = WeaponFX(fx: fx, decals: decals)
        engine.onEvent = { [weak self] e in self?.handle(e) }
        weaponFX.flash = { [weak self] o in self?.setFlash(o) }
        updateCustomCrop()        // 還原的自訂照片在背景裁邊
    }

    /// 選武器（沒解鎖的退回拳頭）
    func selectWeapon(rawID: String) {
        let id = WeaponID(rawValue: rawID) ?? .fist
        weapon = Weapons.weapon(weaponProgress.isUnlocked(id) ? id : .fist)
    }

    private func setFlash(_ opacity: Double, fade: TimeInterval = 0.17) {
        flash = opacity
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeOut(duration: fade)) { self?.flash = 0 }
        }
    }

    private func award(_ gained: [Weapon]) {
        for w in gained {
            runWeapons.append(w)
            coach.showMessage(CoachMessage(key: "w-\(w.id.rawValue)", icon: w.emoji,
                                           text: String(format: L("unlock_weapon_toast"), w.name)))
            AudioEngine.shared.play("chime", combo: 0)
        }
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        newRun()
    }

    // MARK: - 一輪

    func newRun(mode newMode: GameMode? = nil) {
        burstToken += 1
        finishToken += 1
        stopTicking()
        if let newMode { mode = newMode }
        result = nil
        runWeapons = []
        decalClearWork?.cancel()
        decalClearWork = nil
        decals.clear()
        ghosts = []
        koText = nil
        faceTransform = FaceTransform()
        coolingActive = false
        isCharging = false
        weakSpot = nil
        mokugyoFace = Int.random(in: 1...3)
        coach.hide()
        coach.hideMessage()         // 解鎖提示不帶進下一輪
        engine.reset(mode: mode, characterIndex: startingCharacter)
        sync()
        if mode == .rage { coach.show(.tap) }
    }

    /// 圖鑑：指定下一輪的起始角色並立刻開新一輪（木魚模式會切回憤怒模式）
    func startRun(withCharacter index: Int) {
        // 只有待機（還沒打第一下）才能從圖鑑開新一輪；結算、廣告關卡期間不行，免得漏掉紀錄
        guard engine.phase == .idle, result == nil else { return }
        let clamped = max(0, min(index, unlockedCount - 1))
        startingCharacter = clamped
        settings.startingCharacter = clamped
        newRun(mode: .rage)
    }

    // MARK: - 輸入

    func pressBegan(at p: CGPoint) {
        guard result == nil else { return }
        pressPoint = p
        pressBeganUptime = Self.now()
        engine.pressBegan(at: p, now: pressBeganUptime)
        ensureTicking()
        sync()
    }

    func pressMoved(to p: CGPoint) {
        engine.pressMoved(to: p, now: Self.now())
    }

    func pressEnded(at p: CGPoint) {
        let r = engine.pressEnded(at: p, now: Self.now())
        if case .charge(let hits, let origin) = r {
            onGesture?()
            startBurst(hits: hits, origin: origin)
        }
        ensureTicking()
        sync()
    }

    var isPressing: Bool { engine.isPressing }

    /// 觸控被取消（來電、Siri、進背景…）
    func pressCancelled() {
        engine.pressCancelled(now: Self.now())
        ensureTicking()
        sync()
    }

    /// VoiceOver 預設動作：在打擊區中央點一下
    func performAccessibilityTap() {
        guard result == nil else { return }
        let center = faceCenter
        pressBegan(at: center)
        pressEnded(at: center)
    }

    private func startBurst(hits: Int, origin: CGPoint) {
        let token = burstToken
        for i in 0..<hits {
            after(Double(i) * GameConfig.chargeHitInterval) { [weak self] in
                guard let self, token == self.burstToken, self.result == nil else { return }
                self.engine.chargeHit(origin: origin, now: Self.now())
                self.ensureTicking()
                self.sync()
            }
        }
    }

    // MARK: - tick

    private func ensureTicking() {
        #if DEBUG
        if debugFrozen { return }
        #endif
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: SessionConfig.tickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.tick(now: Self.now())
            self.sync()
            if !self.engine.needsTick { self.stopTicking() }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func sync() {
        if enemy != engine.enemy { enemy = engine.enemy }
        if combo != engine.combo { combo = engine.combo }
        if merit != engine.merit { merit = engine.merit }
        let m = GameConfig.multiplier(forCombo: engine.combo)
        if multiplier != m { multiplier = m }
        if phase != engine.phase { phase = engine.phase }
        if isCharging != engine.isCharging { isCharging = engine.isCharging }
        if weakSpot != engine.weakSpot { weakSpot = engine.weakSpot }
        if mode != engine.mode { mode = engine.mode }
    }

    // MARK: - 畫面用的計算

    /// 背景熱度 0...1：停手與結算時為 0
    var heat: Double {
        guard mode == .rage, phase == .fighting else { return 0 }
        return GameConfig.heat(forCombo: combo)
    }

    static func faceSide(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * SessionConfig.faceFraction
    }

    func faceImage(for enemy: Enemy) -> Image {
        if mode == .mokugyo { return FaceCrop.image(named: "mokugyo\(mokugyoFace)") }
        if useCustomImage, let custom = customImage, !enemy.isNewCharacter {
            return Image(uiImage: customCropped ?? custom)      // 還沒裁好先用原圖
        }
        return FaceCrop.image(named: "face\(enemy.characterIndex + 1)")
    }

    func faceImage(forCharacter index: Int) -> Image { FaceCrop.image(named: "face\(index + 1)") }

    /// 自訂照片裁邊：背景處理，完成時照片沒換掉才採用；照片關掉就釋放
    private func updateCustomCrop() {
        // 換照片時先清掉舊的裁好版本（裁好前顯示新照片的原圖，不會閃過舊照片）
        if customCropped != nil { customCropped = nil }
        guard let image = customImage else { return }
        FaceCrop.cropAsync(image) { [weak self] cropped in
            guard let self, self.customImage === image else { return }
            self.customCropped = cropped
        }
    }

    var enemyLabel: String {
        switch enemy.kind {
        case .boss: return L(enemy.isNewCharacter ? "enemy_label_boss_new" : "enemy_label_boss")
        case .armor: return L("enemy_label_armor")
        case .normal: return String(format: L("enemy_label_n"), enemy.ordinal)
        }
    }

    var rageText: String {
        switch GameConfig.rageLevel(forCombo: combo) {
        case .calm: return L("rage_calm")
        case .mid: return L("rage_mid")
        case .high: return L("rage_high")
        case .max: return L("rage_max")
        case .promax: return L("rage_promax")
        }
    }

    // MARK: - 事件處理

    private func handle(_ e: GameEvent) {
        // 解鎖統計（只在憤怒模式累計）
        for stat in WeaponProgress.increments(for: e, mode: mode) {
            award(weaponProgress.record(stat))
        }
        switch e {
        case .runStarted:
            coach.done(.tap)
        case .hit(let h):
            handleHit(h)
        case .armorOff(let at):
            let c = faceCenter, side = faceSide
            fx.floatText(at: CGPoint(x: c.x, y: c.y - side * 0.38), "🪖", size: 46,
                         vx: CGFloat(tiltSign) * 5, vy: -7, gravity: 0.5, friction: 0.97, life: 0.9)
            fx.floatText(at: CGPoint(x: c.x, y: c.y - side * 0.62), L("float_helmet_off"), size: 20)
            _ = at
            coach.done(.armor)
        case .comboMilestone(let n):
            fx.floatText(at: CGPoint(x: faceCenter.x, y: faceCenter.y - faceSide * 0.62),
                         String(format: L("float_combo_milestone"), n), size: 34, color: .white, shadowed: true)
        case .weakSpotShown:
            coach.show(.weak, force: true)
        case .weakSpotHidden(let hit):
            if hit { coach.done(.weak) } else { coach.hide(ifShowing: .weak) }
        case .ko(let k):
            handleKO(k)
        case .enemySpawned(let spawned, let dropped):
            handleSpawn(spawned, dropped: dropped)
        case .characterUnlocked(let total):
            unlockedCount = total
            defaults.set(total, forKey: "unlockedCount")
        case .chargingStarted:
            HapticsEngine.shared.playLightTick()
        case .chargingStopped, .chargeReleased:
            break
        case .coolingStarted:
            coolingActive = true
        case .coolingCancelled:
            coolingActive = false
        case .finished(let summary):
            coolingActive = false
            defaults.set(engine.bestCombo, forKey: "bestCombo")
            defaults.set(engine.bestRun, forKey: "bestRunKO")
            coach.hide()
            decals.clear()
            weaponProgress.flush()
            finishToken += 1
            let token = finishToken
            let show = { [weak self] in
                // 廣告期間若已開新一輪（或已顯示過）就不再顯示
                guard let self, token == self.finishToken, self.result == nil,
                      self.engine.phase == .finished else { return }
                AudioEngine.shared.play("chime", combo: 0)
                self.result = summary
            }
            if let gate = resultGate { gate(show) } else { show() }
        }
    }

    private func handleSpawn(_ spawned: Enemy, dropped: Bool) {
        let apply = {
            self.enemy = spawned
            self.faceID += 1
            self.faceTransform = FaceTransform()
        }
        if dropped && !reduceMotion {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { apply() }
        } else {
            apply()
        }
        // 殘留痕跡：新角色落下時清掉（擊退約 0.45 秒後），新一輪則立刻清
        decalClearWork?.cancel()      // 連續擊退：取消前一個還沒執行的清除，避免誤清新痕跡
        decalClearWork = nil
        if dropped {
            let work = DispatchWorkItem { [weak self] in self?.decals.clear() }
            decalClearWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + DecalConfig.koClearDelay, execute: work)
        } else {
            decals.clear()
        }
        coach.hide(ifShowing: .armor)
        if spawned.kind == .armor { coach.show(.armor, force: true) }
        if dropped && spawned.kind == .boss {
            fx.floatText(at: CGPoint(x: faceCenter.x, y: faceCenter.y - faceSide * 0.66), L("float_boss_enter"), size: 36,
                         color: .white, shadowed: true)
        }
    }

    private func handleHit(_ h: HitEvent) {
        if h.kind != .charge { onGesture?() }
        onCombo?(h.combo)
        let moku = mode == .mokugyo
        if moku {
            AudioEngine.shared.play("kokoko", combo: 0)
        } else {
            let audio = AudioEngine.shared
            if h.blocked {
                audio.play("clang", combo: 0)                       // 鏘：金屬聲取代打擊聲
            } else {
                if h.kind == .swipe { audio.play("whoosh", combo: 0) }
                audio.play(weapon.sound.hit, combo: weapon.sound.pitchesWithCombo ? h.combo : 0)
                if h.crit { audio.play("ping", combo: 0) }
            }
        }
        HapticsEngine.shared.play(power: CGFloat(h.power), style: moku || h.blocked ? .scaled : weapon.haptic)
        reactFace(h, mokugyo: moku)

        let power = CGFloat(h.power)
        if moku {
            fx.impact(at: h.location, power: power, allowShake: false, lightBackground: true)
            fx.floatText(at: CGPoint(x: h.location.x, y: h.location.y - 24), L("float_merit"), size: 20,
                         color: SessionConfig.mokugyoTextColor)
            return
        }

        let allowShake = !reduceMotion
        if h.kind == .swipe { fx.trail(from: h.from, to: h.location) }
        if h.blocked {
            fx.impact(at: h.location, power: 0.5, allowShake: allowShake && weapon.shakesScreen)
            fx.floatText(at: CGPoint(x: h.location.x, y: h.location.y - 28), L("float_clang"), size: 26)
        } else {
            weaponFX.hit(weapon, at: h.location, power: power)
            let at = CGPoint(x: h.location.x + CGFloat.random(in: -30...30), y: h.location.y - 30)
            if h.crit {
                fx.floatText(at: CGPoint(x: h.location.x, y: h.location.y - 34), L("float_crit"), size: 30)
            } else if h.kind == .swipe {
                fx.floatText(at: CGPoint(x: h.location.x, y: h.location.y - 30), L("float_slap"), size: 30)
            } else {
                fx.floatText(at: at, FXConfig.emojis.randomElement() ?? "💢", size: 30)
            }
        }

        // 情境提示
        coach.done(h.kind == .tap ? .tap : h.kind == .swipe ? .swipe : .hold)
        if h.crit { coach.done(.weak) }
        if coach.current == nil {
            if engine.taps >= 8 && !coach.isDone(.swipe) {
                coach.show(.swipe)
            } else if coach.isDone(.swipe) && h.combo >= 10 && !coach.isDone(.hold) {
                coach.show(.hold)
            }
        }
    }

    private func reactFace(_ h: HitEvent, mokugyo: Bool) {
        var t = FaceTransform()
        var resetAfter = SessionConfig.tapFaceReset
        if mokugyo {
            t.scale = 0.9
        } else if h.kind == .swipe {
            t.rotation = Double(h.direction) * 38
            t.scale = 1.1
            t.dx = reduceMotion ? 0 : CGFloat(h.direction) * stage.width * SessionConfig.swipeFaceShift
            resetAfter = SessionConfig.swipeFaceReset
        } else {
            tiltSign = -tiltSign
            t.rotation = tiltSign * Double.random(in: 6...18) * h.power
            t.scale = 1.08 + 0.06 * CGFloat(h.power)
        }
        faceReset?.cancel()
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { faceTransform = t }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { self?.faceTransform = FaceTransform() }
        }
        faceReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + resetAfter, execute: work)
    }

    private func handleKO(_ k: KOEvent) {
        let impacts = k.boss ? SessionConfig.bossKoImpacts : SessionConfig.koImpacts
        let power = k.boss ? SessionConfig.bossKoImpactPower : SessionConfig.koImpactPower
        for _ in 0..<impacts {
            let p = CGPoint(x: stage.width * CGFloat.random(in: 0.2...0.8),
                            y: faceCenter.y + faceSide * CGFloat.random(in: -0.3...0.3))
            fx.impact(at: p, power: power, allowShake: false)
        }
        HapticsEngine.shared.play(power: k.boss ? SessionConfig.bossKoHapticPower : SessionConfig.koHapticPower)
        AudioEngine.shared.play(weapon.sound.ko, combo: 0)
        // 擊退的全螢幕白閃：和武器的白閃共用節流（每秒最多 3 次、減少動態效果時不閃）。
        // 要在 knockOut 之前，而且 KO 優先：同一瞬間最後一下的武器白閃會被它蓋過。
        if weaponFX.allowFlash(ko: true) { setFlash(0.95, fade: 0.5) }
        weaponFX.knockOut(weapon)
        if !reduceMotion {
            // 泡泡紙刻意保持安靜：擊退也不晃畫面
            if weapon.shakesScreen { fx.shake(amount: k.boss ? FXConfig.bossKoShake : FXConfig.koShake) }
            let ghost = Ghost(image: faceImage(for: enemy), sign: tiltSign)
            ghosts.append(ghost)
            after(SessionConfig.ghostDuration) { [weak self] in self?.ghosts.removeAll { $0.id == ghost.id } }
        }
        koCounter += 1
        let callout = Callout(id: koCounter,
                              text: k.boss ? L("float_boss_ko") : String(format: L("float_ko"), k.run))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { koText = callout }
        after(k.boss ? SessionConfig.bossKoTextDuration : SessionConfig.koTextDuration) { [weak self] in
            guard self?.koText?.id == callout.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.koText = nil }
        }
    }

    private func after(_ seconds: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }
}

#if DEBUG
// MARK: - 截圖用的展示狀態（只在 DEBUG；啟動參數 `-uiDemoState <name>`）
extension GameSession {
    /// 用真實的引擎事件打出指定狀態，然後停住（不再 tick），方便截圖。
    func runDemo(_ name: String) {
        func taps(_ n: Int, until stop: (() -> Bool)? = nil) {
            let c = faceCenter
            for _ in 0..<n {
                if let stop, stop() { break }
                pressBegan(at: c)
                pressEnded(at: c)
            }
        }
        switch name {
        case "fever":
            debugFrozen = true
            taps(36)
        case "armor":
            debugFrozen = true
            taps(4000, until: { self.enemy.kind == .armor })
        case "boss":
            debugFrozen = true
            taps(4000, until: { self.enemy.kind == .boss })
        case "bossdmg":
            debugFrozen = true
            taps(4000, until: { self.enemy.kind == .boss })
            taps(4000, until: { self.enemy.hp / max(self.enemy.maxHP, 1) < 0.3 })
        case "damage":
            debugFrozen = true
            taps(4000, until: { self.enemy.hp / max(self.enemy.maxHP, 1) < 0.3 })
        case "charge":
            pressBegan(at: faceCenter)
        case "cooling":
            debugFrozen = true
            taps(14)
            engine.tick(now: Self.now() + GameConfig.idleToCooling + 0.1)
            sync()
        case "result":
            taps(25)       // 以真實的計時器收尾（約 3 秒後出現結算頁）
        case "resultunlock":
            // 直接組一份有新紀錄、新角色、新武器的結算（只為了截圖）
            debugFrozen = true
            taps(10)
            runWeapons = [Weapons.weapon(.slipper)]
            result = RunSummary(mode: .rage, koCount: 4, taps: 132, maxCombo: 41, seconds: 48, merit: 0,
                                newBestCombo: 41, newBestRun: 4, unlockedCharacters: [3])
        case "mokugyo":
            newRun(mode: .mokugyo)
            debugFrozen = true
            taps(8)
        default:
            break
        }
    }
}
#endif
