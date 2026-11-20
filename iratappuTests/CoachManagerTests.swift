import Testing
import Foundation
@testable import IRAPPO

struct CoachManagerTests {
    private func makeManager() -> CoachManager {
        let name = "coach-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return CoachManager(defaults: defaults)
    }

    @Test func showsAtMostTwiceEvenWhenHiddenEarly() {
        let c = makeManager()
        c.show(.weak)
        #expect(c.current == .weak)
        c.hide()                                   // 計時器還沒跑就被收掉
        c.show(.weak)
        #expect(c.current == .weak)                // 第二次
        #expect(c.isDone(.weak))                   // 第二次顯示當下就標記完成
        c.hide()
        c.show(.weak)
        #expect(c.current == nil)                  // 第三次不再出現
    }

    @Test func firstShowDoesNotMarkDone() {
        let c = makeManager()
        c.show(.armor, force: true)
        #expect(!c.isDone(.armor))
    }

    @Test func doneIsPermanent() {
        let c = makeManager()
        c.show(.tap)
        c.done(.tap)
        #expect(c.current == nil)
        c.show(.tap)
        #expect(c.current == nil)
    }

    @Test func hideDoesNotResetCounters() {
        let c = makeManager()
        c.show(.swipe)
        c.hide()
        c.hide()
        c.show(.swipe)
        c.hide()
        c.show(.swipe)
        #expect(c.current == nil)
    }

    @Test func onlyOneAtATimeUnlessForced() {
        let c = makeManager()
        c.show(.tap)
        c.show(.swipe)
        #expect(c.current == .tap)
        c.show(.armor, force: true)
        #expect(c.current == .armor)
    }

    @Test func hideIfShowingOnlyHidesThatKey() {
        let c = makeManager()
        c.show(.tap)
        c.hide(ifShowing: .weak)
        #expect(c.current == .tap)
        c.hide(ifShowing: .tap)
        #expect(c.current == nil)
    }

    @Test func unlockMessageSurvivesHintHiding() {
        let c = makeManager()
        c.showMessage(CoachMessage(key: "w-hammer", icon: "🔨", text: "unlocked"))
        c.show(.tap)
        c.hide()
        c.done(.tap)
        c.hide(ifShowing: .tap)
        #expect(c.message?.key == "w-hammer")
        c.hideMessage()
        #expect(c.message == nil)
    }
}
