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
    @Environment(\.scenePhase) private var scenePhase // <-- 移到這裡

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
                        AppOpenAdManager.shared.showAdIfAvailable()
                    }
                }
                .onChange(of: scenePhase) { newPhase, _ in
                    if newPhase == .active {
                        AppOpenAdManager.shared.showAdIfAvailable()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
