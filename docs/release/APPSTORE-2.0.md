# IRAPPO 2.0：App Store Connect 提交資料

照 App Store Connect 的欄位順序排好，可以直接複製貼上。字數上限標在括號裡，下面的文案都在上限內。

---

## 0. 上傳前的清單

| # | 項目 | 狀態 |
|---|---|---|
| 1 | 版本號 2.0（build 1） | ✅ 已設定 |
| 2 | 插頁式廣告 ID `ca-app-pub-9275380963550837/7595394220`（只在 Release 使用） | ✅ |
| 3 | 隱私權清單 `PrivacyInfo.xcprivacy`（宣告 UserDefaults、系統開機時間 API） | ✅ 新增 |
| 4 | iPhone 只支援直向 | ✅ |
| 5 | Archive | ✅ `~/Library/Developer/Xcode/Archives/` 底下的 `IRAPPO 2.0.xcarchive` |
| 6 | 上傳 | ⬜ 你操作，見第 1 節 |
| 7 | 截圖 6.3 吋 1206 × 2622 | ✅ 放在 `docs/release/screenshots/<語言>/` |

## 1. 上傳 build（約 5 分鐘）

1. 打開 Xcode，選 Window → Organizer → Archives，點 `IRAPPO 2.0`。
2. 依序選 Distribute App → App Store Connect → Upload，其他都用預設值，一直按 Next。簽章選 Automatically manage signing。
3. 等 10 到 30 分鐘，build 會出現在 App Store Connect →（App）→ TestFlight，處理完才能選。
4. 出口合規問題：App 只用了系統內建的 HTTPS，沒有自己的加密功能。回答「不使用加密」，或選「僅使用豁免的加密」。

## 2. 新增版本

App Store Connect → 你的 App → 左側「＋」→ iOS → 版本號輸入 `2.0`。

---

## 3. 各語言的商店資訊

App 支援 5 種語言。下面準備了 4 種：日文、繁體中文（台灣）、簡體中文、英文。
- 在 App Store Connect 右上角的語言選單，新增「簡體中文」。
- 香港繁體可以先不建立商店頁，會顯示主要語言的內容。
- 名稱和副標題如果想沿用目前上架的版本，就不用改。

### 🇯🇵 日本語

**名稱（30 字）**
```
イライラタップ：IRAPPO ストレス発散
```

**副標題（30 字）**
```
叩いて撃退、怒りをスッキリ
```

**宣傳文字（170 字，隨時可以改，不需要重新審查）**
```
2.0 大型アップデート！連続撃退モード、魔王、6種類の武器、図鑑が登場。タップ・スワイプ・長押しでイライラを全部ぶつけよう。
```

**描述（4000 字）**
```
イライラしたら、ガマンしないで叩こう。

IRAPPO は、ムカついたその瞬間に開いて、画面をタップするだけでスッキリできるストレス発散アプリです。広告ブロックもチュートリアルもなし。開いたらすぐ叩けます。

■ 2.0 の新しい遊び方
・連続撃退：相手の体力をゼロにすると「撃退！」。次の相手がすぐ落ちてくるので、手を止めずに叩き続けられます
・タップ／スワイプ／長押し：タップはパンチ、スワイプはビンタ（2.5 倍）、長押しはためパンチ
・コンボ：10 コンボで 1.5 倍、30 で 2 倍、60 で 3 倍。画面がどんどん赤く熱くなります
・弱点：黄色い円を叩くとクリティカル
・鉄頭と魔王：ヘルメットはスワイプで外せる。4 体目ごとに魔王が登場
・手を止めたら終了：3 秒止めるとリザルト。今の気分を記録できます

■ 6 種類の武器
こぶし、ビーチサンダル、ハンマー、雷、キーボード、プチプチ。
ダメージはすべて同じで、変わるのは見た目と音と叩いた跡だけ。その日の気分で選べます。遊ぶほど解放されます。

■ 図鑑
魔王を倒すと新しいキャラが図鑑に加わります。全 18 キャラ。自分で選んだ写真を相手にすることもできます（写真は端末の中だけで処理され、外部に送信されません）。

■ 木魚モード
人前で叩きたいときは木魚モード。ポクポク叩いて「功徳 +1」。

■ 記録
撃退数、最高コンボ、気分の変化を毎日記録。7 日間のグラフで振り返れます。

・本体のサイレントスイッチに対応しています
・「視差効果を減らす」がオンのときは、画面の揺れやフラッシュを抑えます
・無料（広告付き）
```

**關鍵字（上限 100 bytes，日文、中文一個字算 3 bytes；用半形逗號分隔，不要加空格。三種語言都已經在上限內）**
```
ストレス発散,イライラ,怒り,叩く,連打,パンチ,解消,スッキリ,木魚
```

**此版本新功能（What's New）**
```
大型アップデート 2.0
・連続撃退モード：倒すと次の相手が登場。魔王と鉄頭も
・タップ／スワイプ／長押しの 3 種類の攻撃とコンボ倍率
・6 種類の武器（エフェクト・音・跡が変わる）
・キャラ図鑑、自分の写真も相手にできる
・毎回の記録と気分のグラフ
・音と振動をつくり直し、連打しても途切れない
・画面デザインを一新
```

### 🇹🇼 繁體中文

**名稱**
```
IRAPPO 怒氣歸零：打一打就消氣
```
**副標題**
```
連打擊退，把火氣打掉
```
**宣傳文字**
```
2.0 大改版！連續擊退、魔王、六種武器、圖鑑全新登場。點、滑、長按，把今天的火氣全部打出來。
```
**描述**
```
生氣的時候，不要忍，打出來。

IRAPPO 是一打開就能開打的紓壓 App。沒有開場廣告，也沒有教學頁，點下去就是一拳。

■ 2.0 新玩法
・連續擊退：把對手的血量打光就「擊退！」，下一個對手馬上掉下來，手不用停
・點／滑／長按：點是拳頭，滑是巴掌（2.5 倍），長按是蓄力重拳
・連擊：10 下 ×1.5、30 下 ×2、60 下 ×3，畫面越打越紅
・弱點：點中黃圈就是爆擊
・鐵頭和魔王：頭盔要用滑的打掉，每 4 個對手出現一次魔王
・停手就收工：停 3 秒結算，順便記下現在的心情

■ 六種武器
拳頭、藍白拖、鐵鎚、雷電、鍵盤、泡泡紙。
傷害完全一樣，差在打下去的畫面、聲音和留下的痕跡。挑今天想要的出氣方式，越玩解鎖越多。

■ 圖鑑
打倒魔王就把新角色收進圖鑑，共 18 個。也可以用自己選的照片當對手（照片只在手機裡處理，不會上傳）。

■ 木魚模式
不方便大力打的時候，切到木魚模式，叩叩叩，功德 +1。

■ 紀錄
每天的擊退數、最高連擊、心情變化，用 7 天圖表回顧。

・跟隨實體靜音鍵
・開啟「減少動態效果」時，不震畫面、不白閃
・免費（含廣告）
```
**關鍵字**
```
紓壓,解壓,生氣,出氣,發洩,打人,連打,點擊,木魚,功德,消氣,減壓,遊戲,療癒
```
**此版本新功能**
```
2.0 大改版
・連續擊退：打倒一個馬上換下一個，還有魔王和鐵頭
・點、滑、長按三種出手，連擊越高傷害越高
・六種武器，特效、聲音、痕跡都不同
・角色圖鑑，也能用自己的照片
・每輪紀錄與心情圖表
・聲音與震動重做，連打不斷音
・全新畫面設計
```

### 🇨🇳 简体中文

**名稱**
```
IRAPPO 怒气归零：打一打就消气
```
**副標題**
```
连打击退，把火气打掉
```
**宣傳文字**
```
2.0 大改版！连续击退、魔王、六种武器、图鉴全新登场。点、滑、长按，把今天的火气全部打出来。
```
**描述**
```
生气的时候，不要忍，打出来。

IRAPPO 是一打开就能开打的解压 App。没有开屏广告，也没有教学页，点下去就是一拳。

■ 2.0 新玩法
・连续击退：把对手的血量打光就"击退！"，下一个对手马上掉下来，手不用停
・点／滑／长按：点是拳头，滑是巴掌（2.5 倍），长按是蓄力重拳
・连击：10 下 ×1.5、30 下 ×2、60 下 ×3，画面越打越红
・弱点：点中黄圈就是暴击
・铁头和魔王：头盔要用滑的打掉，每 4 个对手出现一次魔王
・停手就收工：停 3 秒结算，顺便记下现在的心情

■ 六种武器
拳头、蓝白拖、铁锤、雷电、键盘、泡泡纸。
伤害完全一样，差在打下去的画面、声音和留下的痕迹。挑今天想要的出气方式，越玩解锁越多。

■ 图鉴
打倒魔王就把新角色收进图鉴，共 18 个。也可以用自己选的照片当对手（照片只在手机里处理，不会上传）。

■ 木鱼模式
不方便大力打的时候，切到木鱼模式，咚咚咚，功德 +1。

■ 记录
每天的击退数、最高连击、心情变化，用 7 天图表回顾。

・跟随实体静音键
・开启"减弱动态效果"时，不震屏幕、不白闪
・免费（含广告）
```
**關鍵字**
```
解压,减压,生气,出气,发泄,连打,点击,木鱼,功德,消气,游戏,治愈,打脸
```
**此版本新功能**
```
2.0 大改版
・连续击退：打倒一个马上换下一个，还有魔王和铁头
・点、滑、长按三种出手，连击越高伤害越高
・六种武器，特效、声音、痕迹都不同
・角色图鉴，也能用自己的照片
・每轮记录与心情图表
・声音与震动重做，连打不断音
・全新画面设计
```

### 🇺🇸 English

**Name**
```
IRAPPO: Stress Relief Tapper
```
**Subtitle**
```
Tap, smash, and cool down
```
**Promotional Text**
```
Version 2.0 is here: knockout streaks, bosses, six weapons and a character collection. Tap, swipe and hold to let it all out.
```
**Description**
```
Angry? Don't bottle it up. Tap it out.

IRAPPO is a stress-relief app you can open the moment something gets to you. No launch ads, no tutorial wall. One tap and you're punching.

NEW IN 2.0
• Knockout streaks: empty a rival's health bar for a KNOCKOUT, and the next one drops right in.
• Tap, swipe, hold: tap to punch, swipe to slap (2.5x), hold for a charged blow.
• Combos: 10 hits = 1.5x, 30 = 2x, 60 = 3x. The screen heats up as you go.
• Weak spots: hit the yellow ring for a critical.
• Helmets and bosses: swipe to knock helmets off; a boss shows up every fourth rival.
• Stop to finish: pause for 3 seconds to see your results and log your mood.

SIX WEAPONS
Fist, flip-flop, hammer, lightning, keyboard and bubble wrap. They all deal the same damage. What changes is the look, the sound and the marks they leave. Unlock more as you play.

CHARACTER COLLECTION
Beat a boss to add a new face to your collection, 18 in all. You can also use a photo of your choice. Photos are processed on your device and never uploaded.

WOODBLOCK MODE
Somewhere quiet? Switch to woodblock mode and tap for good karma.

RECORDS
Track daily knockouts, best combos and how you felt, with a 7-day chart.

• Respects the silent switch
• Reduce Motion turns off screen shake and flashes
• Free, ad-supported
```
**Keywords**
```
stress,relief,anger,tap,smash,punch,relax,calm,rage,fidget,clicker,mokugyo,woodblock,karma,vent
```
**What's New**
```
IRAPPO 2.0, a complete overhaul:
• Knockout streaks with helmets and bosses
• Tap, swipe and hold attacks with combo multipliers
• Six weapons with their own effects, sounds and marks
• Character collection, including your own photo
• Per-session records and mood chart
• Rebuilt sound and haptics that never cut out
• Brand-new design
```

---

## 4. 截圖

- **尺寸**：1206 × 2622，對應 iPhone 6.3 吋。只上傳這一組，App Store 會自動縮放給其他尺寸的 iPhone。
- **上傳方式**：每種語言把 `docs/release/screenshots/<語言>/` 底下的 6 張依 01 到 06 的順序拖進去。
  - `ja`：日文
  - `zh-Hant`：繁體中文
  - `zh-Hans`：簡體中文
  - `en`：英文

| 檔名 | 畫面 |
|---|---|
| 01_idle | 待機（開打前） |
| 02_fever | 連擊 FEVER、鐵頭、弱點 |
| 03_boss | 魔王登場 |
| 04_resultunlock | 結算：新紀錄、新角色、新武器 |
| 05_weapons | 武器選單 |
| 06_dex | 圖鑑 |

- **App 預覽影片**：可以不放。
- **iPad 截圖**：App 支援 iPad。如果 App Store Connect 要求 iPad 13 吋截圖（2064 × 2752），再告訴我，我用 iPad 模擬器補拍。

## 5. 一般資訊

| 欄位 | 值 |
|---|---|
| 主要類別 | 健康塑身（Health & Fitness）。原本的類別如果是「娛樂」，維持原本的也可以 |
| 次要類別 | 遊戲 → 休閒（Games › Casual） |
| 版權 | `2026 Chia-Wei Chang` |
| 支援網址 | `https://changch223.github.io` |
| 行銷網址 | `https://appfreelife.com/?p=22` |
| 隱私權政策網址 | README 裡的 Notion 頁面（沿用現在的）。請確認內容有寫到「使用 Google AdMob 顯示廣告」和「自訂照片只存在本機」 |
| 價格 | 免費 |

## 6. 年齡分級問卷

| 問題 | 回答 |
|---|---|
| 卡通或奇幻暴力 | **不常／輕微**：打卡通人物的臉，沒有血腥 |
| 寫實暴力 | 無 |
| 其他（性、恐怖、藥物、賭博、髒話等） | 全部選無 |
| 無限制網頁存取 | 否 |
| 使用者產生內容、聊天 | 否 |
| 廣告 | 是（有第三方廣告） |
| 結果 | 預期 **9+** |

## 7. App 隱私（「資料類型」問卷）

依據是 Google 官方的 AdMob App Store 揭露指引。App 本身不收集任何資料：照片、紀錄、設定都只存在手機裡。要申報的都來自 Google Mobile Ads SDK。

- **會收集資料**：是
- **資料類型和用途**：

| 類型 | 用途 | 與使用者身分連結 | 用於追蹤 |
|---|---|---|---|
| 位置 → 大略位置 | 第三方廣告、分析 | 否 | 否 |
| 識別碼 → 裝置 ID | 第三方廣告、分析 | 否 | 否 |
| 使用資料 → 產品互動 | 第三方廣告、分析 | 否 | 否 |
| 使用資料 → 廣告資料 | 第三方廣告、分析 | 否 | 否 |
| 診斷 → 當機資料、效能資料、其他診斷資料 | 第三方廣告、分析 | 否 | 否 |

- **「用於追蹤」選否的理由**：App 沒有跳出 ATT 追蹤授權（`NSUserTrackingUsageDescription`），Google 拿不到 IDFA，只能做非個人化的廣告。
- **注意**：如果之後要加 ATT 來提高廣告收益，這裡的「用於追蹤」要改成**是**。

## 8. 審查備註（App Review Information）

- **聯絡人**：填你自己的姓名、電話和 email。這三項只有 Apple 審查人員看得到。
- **需要登入**：否。
- **備註，直接貼上**：

```
IRAPPO is a single-player stress-relief tapping app. No account or login is needed.

How to test:
1. Tap anywhere on the screen to hit the character. Swipe for a slap and press and hold for a charged blow.
2. When the HP bar is empty, the character is knocked out and the next one appears. Every 4th character is a boss.
3. Stop tapping for about 3 seconds to see the result screen.
4. Use the top buttons for Records, Mode (rage or woodblock) and Character collection, and the bottom buttons for Sound, How to play and Weapons.

Custom photo: in the Character collection, the first cell lets the user pick a photo using the system photo picker (PHPicker, so no photo-library permission is needed). Background removal runs on-device with Vision, and the photo is never uploaded.

Ads: Google AdMob banner ads, and an interstitial shown at most once every 3 results, before the result screen. There are no ads at launch.

The violence is cartoon-style and has no blood.
```

## 9. 版本發布方式

- **建議選手動發布**：審查通過後，等你看過實機上的正式版、確認廣告有正常顯示，再按「發布此版本」。
- **分階段發布（7 天）**：建議開啟。如果有問題可以暫停，不會一次影響到所有使用者。

---

## 10. 不擋上架，但建議之後處理

1. **歐盟和英國的廣告同意（GDPR）**
   - Google 要求對這些地區的使用者顯示同意視窗，要用 UMP SDK。
   - 沒有的話，這些地區可能只出很少的廣告或完全沒有廣告，但不影響 App 審查。
   - 做法是在 AdMob 的「隱私權與訊息」建立 GDPR 訊息，然後在 App 裡接上 UMP。如果要做，我可以加上。
2. **暫用音效**：11 個新音效是程式合成的暫用版，建議之後換成正式的音檔。
3. **翻譯**：日文、英文、簡體、香港繁體，建議請母語人士看過一次。
