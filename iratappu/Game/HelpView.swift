import SwiftUI

/// 「？玩法」：兩欄排版，左邊粗體詞、右邊說明
struct HelpView: View {
    @Environment(\.uiScale) private var k

    private let items = ["help_tap", "help_swipe", "help_hold", "help_weak",
                         "help_armor", "help_boss", "help_weapon", "help_combo", "help_finish"]

    var body: some View {
        SheetScaffold(title: L("help_title")) {
            Grid(alignment: .topLeading, horizontalSpacing: 14 * k, verticalSpacing: 14 * k) {
                ForEach(items, id: \.self) { key in
                    GridRow {
                        Text(L("\(key)_title"))
                            .uiFont(18, .black)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(L("\(key)_body"))
                            .uiFont(17, .regular)
                            .lineSpacing(3 * k)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
