# IRAPPO 畫面改版規格（Phase 5：照 HTML 原型重做 UI）

> 設計來源：`docs/redesign/prototype/irappo-prototype-src.html` 第 47–190 行（CSS）與第 248–344 行（手機畫面的 markup）。
> 遊戲規則、數值、引擎、音效、震動、存檔**都不改**（SPEC.md 1–4 階段已通過 QA）。這一階段只換畫面的版面與樣式，外加 3 個修正。
> 原型用 `em` 當單位，手機寬 31em。換算：**1em ≈ 螢幕寬 / 31**（iPhone 17 Pro 402pt → 約 13pt）。下面直接給 pt（以 402pt 寬為準），實作時請用 `UIScreen` 寬或 GeometryReader 等比換算的 `u`，不要寫死。

---

## 0. 三個必修問題（使用者實機回報）

1. **魔王登場時，角色放大並跑到右上角。**
   原因：`StageView` 的 ZStack 裡，魔王光暈 `Circle` 的 frame 是 `side * 1.7`，比 GeometryReader 還大，把 ZStack 撐大；GeometryReader 的內容靠左上對齊，於是整個中心點偏移。
   修法：光暈改成角色的 `.background { }`（不參與版面計算），舞台 ZStack 加 `.frame(width: geo.size.width, height: geo.size.height)`。所有裝飾（光暈、名牌、頭盔、傷痕記號）都不能影響版面大小。**驗收：魔王出現時，角色中心點和普通對手完全相同，只放大 1.14 倍。**
2. **角色太小，要放大約 1.5 倍。**
   原因：`Face/*.png` 是 1000×1000，但臉只佔中間約 21–35%（例：face1 的不透明範圍是 396–603）。
   修法：
   - 載入時把每張臉圖**裁掉透明邊**（alpha bbox，四周各留 6% 邊），結果快取在記憶體。自訂照片也一樣裁。
   - 裁好之後，角色框 `faceSide = min(stageWidth × 0.62, stageHeight × 0.62)`，做成常數 `SessionConfig.faceFraction`。目標：在 iPhone 17 Pro 上，臉的可見大小約是目前的 1.5 倍。請用模擬器截圖量新舊兩版，回報實際倍率。
   - 用到 `faceSide` 的地方都要一起檢查：頭盔掉落位置、浮字位置、殘影 `GhostFace`、弱點出現的範圍、木魚縮放。弱點必須落在可見的臉上。
3. **UI 和 HTML 原型完全不一樣** → 照下面第 1–6 節重做。

另外：
4. 紀錄頁的 banner 改用它自己的廣告單元 `ca-app-pub-9275380963550837/7125166187`（StatisticsViewBanner）。主畫面保持 `…/6757899905`。App ID `…~7311831032` 已經在 Info.plist，不用改。

---

## 1. 設計 token（新增 `Game/Theme.swift`）

| token | 值 | 用途 |
|---|---|---|
| `ink` | #1C1014 | 文字、按鈕底、血條 |
| `paper` | #FFFFFF | 白字、sheet 底 |
| `hot` | #FF5548 | 熱度最高 |
| `cool` | #CDEFE8 | 熱度最低、選取底色 |
| `spark` | #FFD43B | 弱點、魔王名牌字、紀錄徽章、FEVER |
| `woodBg` | #FFF1CC | 木魚模式背景 |
| `wood` | #8A5200 | 木魚模式數字 |
| `glass` | paper 72% 不透明 | 上方圓鈕、模式切換、下方 chip |

- 背景熱度：`mix(cool, hot, heat)`，用 OKLab 或 sRGB 線性插值都可以。要取代現在的 `StageStyle.heatColor`（米色到紅）。**背景鋪滿整個螢幕（ignoresSafeArea）**，不再是圓角框裡的一塊。
- 字型：數字（連擊、血量、結算數字）用 `.system(…, weight: .black, design: .rounded).monospacedDigit()`。其他文字用 `.system(weight: .bold / .heavy)`。不另外放字型檔。
- 深色模式：app 畫面永遠是亮面（角色是黑線稿），所以強制 `.preferredColorScheme(.light)`，或所有顏色都用上面的固定值。

## 2. 主畫面版面（取代 ContentView 的 body）

不使用 NavigationStack 或工具列。整個螢幕是打擊區：手勢放在最底層的全螢幕觸控層，按鈕疊在上面，按鈕優先接收點擊。

```
┌──────────────────────────────┐ safe area top
│ (📊)   [💢 發洩|🪵 木魚]   (▦) │ top：圓鈕 44pt；模式切換是 glass 膠囊
│ 第 3 個 ▬▬▬▬▬▬▬▬▬▬▬▬▬▬    120 │ hp：標籤 / 血條 / 數字
│                                │
│              37                │ combo：大數字在角色後面上方
│            ProMax              │
│          ┌────────┐            │
│          │  face  │ ←頭盔/名牌  │ 角色在舞台正中央偏下
│          └────────┘            │
│                                │
│     點、滑、長按，都算數         │ hint／蓄力字／冷卻條／提示膠囊（同一位置）
│ [🔊 聲音開]  [？玩法]  [👊 拳頭] │ foot chips
│ ═══════ banner 50pt ═══════   │
└──────────────────────────────┘ safe area bottom
```

各區域（數值以 402pt 寬為準，u ≈ 13pt）：

- **top**：水平間距 21pt，上方貼 safe area 加 8pt。
  - 左邊是紀錄鈕：圓形 57pt（4.4em），glass 底，SF Symbol `chart.bar` 線條風。
  - 右邊是圖鑑鈕：同樣大小，`square.grid.2x2`。
  - 中間是模式切換：glass 膠囊，內距 4.5pt。兩個按鈕「💢 發洩」「🪵 木魚」，16pt bold。選中的按鈕 ink 底、白字、膠囊形。按下就呼叫 `session.newRun(mode:)`。
- **hp 列**：左右內距 26pt，上方 21pt。三欄：
  - 左邊是「第 N 個」，16pt black。
  - 中間是血條：高 14pt，膠囊形，底色 ink 16%，填色 ink，寬度動畫 0.18s。
  - 右邊是數字，20pt rounded black，靠右，固定寬 42pt。
  - 魔王時：血條高 22pt，外框 2.6pt ink，填色是 -45° 斜紋（ink 和 ink 76% 混 hot，各 10pt 寬交替）。
  - 木魚模式：整列不顯示，但保留高度。
- **stage**（佔滿剩下的高度，`position: relative`）：
  - **combo**：靠上，距頂 13pt，在角色**後面**（zIndex 低於角色）。
    - 數字 143pt（11em）rounded black，白色。
    - 下面一行是怒氣等級 `rageText`，20pt black ink。
    - 只在 live 狀態（hitting 或 cooling）顯示，淡入 0.2s。冷卻時降到 35% 不透明。
    - FEVER（連擊 ≥ 30，沿用倍率 ×2 的門檻）：數字改 spark 色加 ink 描邊，角色每 0.5s 黃色 drop-shadow 脈動一次。
    - 木魚模式：數字是 merit，wood 色。
  - **角色**：置中，框邊長依第 0 節第 2 點。位置要往下推：中心在舞台高度約 55% 處，因為上方要留給 combo。
    - 頭盔 🪖：字級 = 框 × 0.36，位置在框頂上方 12%，置中。
    - 魔王名牌：ink 底、spark 字「魔王」，22pt black，字距 0.2em，圓角 6pt，位置在框頂上方 9%，置中。
    - 魔王光暈：角色的 background。徑向漸層 ink 55% 到透明，範圍是框的 1.28 倍，1.2s 呼吸（scale 1 到 1.12，opacity 1 到 0.65）。
    - 魔王的角色框 ×1.14。
    - 傷痕記號（新增）：血量 < 66% 時，左邊 22% 處顯示 🩹，旋轉 -24°，47pt。血量 < 33% 時，右上再加 💫，1.2s 一圈。換新對手時清掉。
  - **擊退字**：「擊退！」（沿用 `koText` 的文字），73pt black，白字加 ink 描邊（用多層 shadow 或 stroke 模擬，約 6pt），旋轉 -8°，位置在舞台 36% 高。
    - 出現動畫：從 scale 2.4 用 spring 落到 1（0.22s）。
    - 白閃：全螢幕白色，從 0.95 淡到 0，0.5s。reduced motion 時不閃。這個白閃要和現有的 `flash` 節流共用。
  - **蓄力**：
    - 蓄力環以**角色中心**為圓心，直徑 = 框 × 1.24。2.6pt 的 ink 線，從 12 點鐘方向順時針填滿，3s 填滿（沿用 `chargeRingFull`）。不再跟著手指。
    - 角色發抖並縮到 0.91。
    - 舞台底部顯示「蓄力中 ・ 連擊保留」，20pt black。
  - **舞台底部的同一個位置**（距底 8pt）一次只顯示一樣，優先順序：
    1. 情境提示膠囊：ink 底、白字 18pt bold、左邊動畫 emoji 26pt、膠囊內距 8/17pt。沿用 `CoachCapsule` 的內容與動畫，只改樣式。
    2. 蓄力字。
    3. 冷卻：「停手就收工 ・ 再打一下繼續」17pt bold，下面一條血條樣式的條，2s 從滿到空。左右各內距 39pt。
    4. 待機提示：「點、滑、長按，都算數」17pt bold。只在 idle 顯示。
- **foot**：左右內距 23pt，下方 8pt，三個 chip 用 space-between 排開。chip 是 glass 膠囊，16pt bold，內距 6/13pt。
  - 左邊：`🔊 聲音開` / `🔇 聲音關`，按了切換 `soundEnabled`。
  - 中間：`？玩法`，打開玩法。
  - 右邊：**武器 chip**，例如 `👊 拳頭`，打開武器選擇。木魚模式顯示 `🪵 木魚`，按了沒反應。
  - 如果有武器的解鎖進度 ≥ 80%，武器 chip 右上角加一個 spark 色小圓點，提醒快解鎖了。
- **live 狀態**（phase 是 hitting 或 cooling）：top 和 foot 在 0.25s 內淡到 0，而且不能點。hint 也一起隱藏。hp 列和 combo 照常顯示。
- **banner**：放在 foot 下面，高 50pt，背景跟著熱度色。live 時照常顯示，不要淡出，否則 AdMob 會算成隱藏廣告。
- **刪掉**：
  - 頂部的三格計數（本次／今日／7 天）。資料改到紀錄頁看。
  - 舊的藍、綠、橘方塊按鈕。
  - 「切換木魚版本」按鈕，已經由模式切換取代。
  - 「使用自訂圖片」按鈕，移到圖鑑。
  - NavigationStack 的 toolbar。
  - 舞台的圓角框。

## 3. 底部 sheet 的共通樣式

全部用 SwiftUI `.sheet`，`.presentationCornerRadius(34)`，`.presentationBackground(paper)`。

- **標題列**：左邊是標題，36pt black。右邊是 ✕ 鈕：圓形 44pt，底色 ink 8%，字 16pt bold。
- **內距**：上下 31pt、左右 26pt；區塊之間間距 18pt。
- **說明文字（lab）**：15pt bold，ink 65%。

## 4. 結算頁（ResultView）

保留覆蓋層的做法，因為全螢幕廣告要從 root 顯示。樣式改成從下方滑上來的白色面板：上方圓角 34pt，`.move(edge: .bottom)`，0.38s。面板後面的舞台變暗：黑色 30%，不要現在的 55%。

面板內容由上到下：

1. **標題**：「呼——打完了。」等，36pt black。沿用現在的標題字串。
2. **四格數字**：擊退／最高連擊／打擊／秒。數字 30pt rounded black，標籤 15pt bold ink 65%。木魚模式改成三格：功德／打擊／秒。
3. **新紀錄徽章**（有才顯示）：spark 底，16pt black，圓角 12pt，內距 6/12pt。
4. **新角色解鎖卡**（這一輪有收進圖鑑才顯示）：cool 底，圓角 18pt。
   - 左邊是新角色的圖 65pt。動畫：從全黑、0.7 倍、-20° 轉成正常，0.9s，延遲 0.3s。
   - 右邊兩行：「新角色加入圖鑑」18pt black，「下一場的對手」14pt bold 70%。
   - 這一輪新解鎖的武器也用同樣的卡片，emoji 放大當作圖。
5. 「現在感覺怎麼樣？」，15pt bold 65%。
6. **三個心情按鈕**，三欄等寬：
   - 底色 ink 7%，圓角 13pt，上面 emoji 23pt、下面文字 15pt bold。
   - 選中時加 2pt ink 框，底色換成 cool。
   - 選項是「😤 還是很氣」「😮‍💨 好一點」「😌 爽了」，請沿用現有的字串 key。
7. **「再來一輪」**：滿寬，ink 底白字，21pt black，圓角 13pt，高約 56pt。

## 5. 其他 sheet

- **圖鑑（DexView）**
  - 「已解鎖 N / 18」放在 lab。
  - 四欄格子，間距 10pt，正方形。格子底色是 hot 22% 混 paper，圓角 16pt，圖片 86%。
  - 目前的起始角色加 4pt ink 外框。
  - 鎖住的格子：底色 ink 8%，圖片全黑、16% 不透明，中間放「?」31pt rounded black 45%。
  - **第一格是「自己的照片」**：沒設定時顯示 ＋ 和「我的照片」，點了打開照片選擇器（沿用 ImagePicker 與去背）。設定之後顯示照片，點了就用照片開新一輪，長按可以「換照片」或「改回預設角色」（`useCustomImage = false`）。
  - 最下面放 lab 說明（取原型第 302 行的文字）。
- **武器（WeaponSheet）**
  - 每把武器一列，圓角 16pt，底色 ink 6%，內距 12/14pt。
  - 每列兩欄：左邊 emoji 39pt；右邊是名稱 19pt black，下面一行描述 15pt、70% 不透明。
  - 選中時加 2pt ink 框，底色 cool。
  - 鎖住時 emoji 灰階 40%，描述換成解鎖條件和進度，例如「擊退 30 個解鎖（12/30）」，再加一條細進度條。
  - 最下面的 lab：「武器不改傷害，只改打下去的樣子和聲音。」
- **玩法（HelpView）**：兩欄排版，左邊粗體詞 18pt black，右邊說明 17pt。內容取原型第 314–322 行，包含「武器：右下角換武器…」那一列。
- **紀錄（StatisticsView）**：從 navigationDestination 改成 sheet，`.large`。
  - 上方三格數字：今天的擊退、打擊、最高連擊。
  - 中間是 row 清單，每列一個項目：最多連續擊退、😌 爽了、😮‍💨 好一點、😤 還是很氣。row 字 18pt，數字粗體，分隔線 ink 12%。
  - 再來是期間切換，保留現有功能，改成和模式切換同款的膠囊。
  - 每日擊退的長條圖：七欄、hot 色、上方圓角。
  - 「全部累計」那一列保留。
  - 最下面放 banner，用第 0 節第 4 點的 ID。

## 6. 動態與無障礙

- reduced motion 開啟時：
  - 不震畫面、不白閃、不做飛出動畫。
  - 光暈、💫、FEVER 不脈動。
  - 新角色卡直接顯示，不播動畫。
  - sheet 和面板改成淡入。
- 所有按鈕都要有 accessibilityLabel，沿用現有的字串 key，缺的就補進 5 種語言。
- 觸控：全螢幕觸控層放在最底下，按鈕在上面。按到按鈕不能算一下打擊；打擊中（live）按鈕已經不能點，所以整個畫面都是打擊區。
- 新字串全部進 `Localizable.strings` 的 5 種語言：en、ja、zh-Hans、zh-Hant、zh-HK。

## 7. 驗收

1. 魔王出現時，角色中心點不偏移，只放大 1.14 倍，放大過程沒有跳動。
2. 臉的可見大小約是改版前的 1.5 倍。附上改版前後兩張 iPhone 17 Pro 模擬器截圖。
3. 用模擬器截下面這些畫面，並排對照 HTML 原型的同一個狀態：
   - 待機
   - 打擊中（combo ≥ 30，FEVER）
   - 鐵頭
   - 魔王
   - 蓄力
   - 冷卻
   - 結算
   - 圖鑑
   - 武器
   - 玩法
   - 紀錄
   - 木魚模式
   - iPhone SE 寬度（375pt），檢查不能爆版
4. 現有 98 個測試全部通過，模擬器和真機 Release 都 build 成功。
5. 弱點只出現在可見的臉上。殘影、頭盔掉落、浮字的位置在新尺寸下都正確。
6. live 時上方和下方的按鈕都點不到；在 idle 時點按鈕，不會算成一下打擊。
