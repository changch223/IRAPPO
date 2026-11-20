import SwiftUI
import SwiftData
import GoogleMobileAds

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if !AppEnvironment.isRunningTests {
            MobileAds.shared.start(completionHandler: nil)
            FaceCrop.preload()          // 背景預先裁好所有臉圖
        }
        return true
    }
}

@main
struct iratappuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([RunRecord.self])
        // 新的 store 名稱：舊版範本的 Item store（default.store）不會被讀到，不需要遷移，啟動不會因為 schema 不同而壞掉。
        let persistent = ModelConfiguration("IRAPPORecords", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [persistent])
        } catch {
            AppLog.store.error("Persistent ModelContainer failed: \(error.localizedDescription, privacy: .public). Falling back to in-memory store; records will not be kept.")
        }
        // 讀不起來時退回記憶體 store：這次執行照常能玩，只是紀錄不會留下
        let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [inMemory])
            AppLog.store.notice("Using in-memory ModelContainer fallback")
            return container
        } catch {
            fatalError("Could not create in-memory ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            // 階段 2：不顯示開啟廣告，第一下之前不放任何東西。
            // 啟動計數由 ContentView 在跨日判斷之後統一處理。
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
