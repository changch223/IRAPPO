import Foundation
import os

enum AppEnvironment {
    /// 以單元測試的 host app 執行時為 true：不要啟動音訊、震動、廣告（測試環境沒有音訊服務，會卡住甚至閃退）
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "IRAPPO"
    static let records = Logger(subsystem: subsystem, category: "records")
    static let store = Logger(subsystem: subsystem, category: "store")
}
