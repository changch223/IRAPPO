import SwiftUI
import SwiftData
import GoogleMobileAds

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        MobileAds.shared.start(completionHandler: nil)
        return true
    }
}

@main
struct iratappuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var previousPhase: ScenePhase? = nil


    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // 起動直後に表示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        AppOpenAdManager.shared.loadAd()
                        AppOpenAdManager.shared.showAdIfAvailable() //已經併入load
                        // 呼叫 AppLaunchCounterManager 的 increment 方法
                        AppLaunchCounterManager.shared.increment()
                    }
                }
                .onChange(of: scenePhase) { newPhase, _ in
                    print("ScenePhase changed to: \(newPhase)")
                    if newPhase == .inactive, let previous = previousPhase {
                        if previous == .background {
                            // 從背景轉為前台，呼叫展示廣告的程式
                            AppOpenAdManager.shared.loadAd()
                            AppOpenAdManager.shared.showAdIfAvailable() //已經併入load
                            // 呼叫 AppLaunchCounterManager 的 increment 方法
                            AppLaunchCounterManager.shared.increment()
                        }
                        // 如果 previous == .active，就表示進入背景，這裡就不呼叫展示廣告
                    }
                    previousPhase = newPhase
                }
            
        }
        .modelContainer(sharedModelContainer)
    }
}
