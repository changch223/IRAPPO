import SwiftUI

/// 圖鑑：第一格是「自己的照片」，後面 18 個角色。未解鎖的只畫剪影，不能點。
struct DexView: View {
    @ObservedObject var session: GameSession
    let onSelect: (Int) -> Void

    @Environment(\.uiScale) private var k
    /// 臉圖裁好時更新
    @ObservedObject private var crops = FaceCrop.shared
    @State private var showingPicker = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10 * k), count: 4)
    }

    private var photo: UIImage? { session.useCustomImage ? session.customImage : nil }

    var body: some View {
        SheetScaffold(title: L("dex_title")) {
            SheetLab(text: String(format: L("dex_unlocked_count"), session.unlockedCount, GameConfig.totalCharacters))

            LazyVGrid(columns: columns, spacing: 10 * k) {
                photoCell
                ForEach(0..<GameConfig.totalCharacters, id: \.self) { i in
                    cell(i)
                }
            }

            SheetLab(text: L("dex_footer"))
        }
        .sheet(isPresented: $showingPicker) {
            ImagePicker(image: $session.customImage, isPresented: $showingPicker,
                        onCancel: { if session.customImage == nil { session.useCustomImage = false } })
        }
    }

    private var cellShape: RoundedRectangle { RoundedRectangle(cornerRadius: 16 * k) }

    private var cellBackground: some View {
        ZStack {
            Theme.paper
            Theme.hot.opacity(0.22)
        }
        .clipShape(cellShape)
    }

    // MARK: 自己的照片

    private func pickPhoto() {
        session.customImage = nil
        session.useCustomImage = true
        showingPicker = true
    }

    @ViewBuilder
    private var photoCell: some View {
        if let photo {
            Button {
                // 用照片開新一輪
                session.useCustomImage = true
                onSelect(session.startingCharacter)
            } label: {
                ZStack {
                    cellBackground
                    Image(uiImage: session.customCropped ?? photo)
                        .resizable().scaledToFit()
                        .padding(5 * k)
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(L("dex_change_photo")) { pickPhoto() }
                Button(L("use_default_image")) { session.useCustomImage = false }
            }
            .accessibilityLabel(L("dex_my_photo"))
        } else {
            Button(action: pickPhoto) {
                VStack(spacing: 2 * k) {
                    Text("＋").uiFont(28, .black, number: true)
                    Text(L("dex_my_photo"))
                        .uiFont(12, .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundColor(Theme.ink.opacity(0.65))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cellShape.fill(Theme.ink.opacity(0.06)))
                .overlay(cellShape.stroke(Theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("dex_my_photo"))
        }
    }

    // MARK: 角色

    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        let unlocked = i < session.unlockedCount
        let selected = unlocked && i == session.startingCharacter
        Button {
            if unlocked { onSelect(i) }
        } label: {
            ZStack {
                if unlocked {
                    cellBackground
                    session.faceImage(forCharacter: i)
                        .resizable().scaledToFit()
                        .padding(5 * k)
                } else {
                    cellShape.fill(Theme.ink.opacity(0.08))
                    // 剪影：全黑、16% 不透明，再稍微模糊，不洩漏臉部細節
                    session.faceImage(forCharacter: i)
                        .renderingMode(.template).resizable().scaledToFit()
                        .padding(5 * k)
                        .foregroundColor(.black.opacity(0.16))
                        .blur(radius: 3)
                    Text("?")
                        .uiFont(31, .black, number: true)
                        .foregroundColor(.black.opacity(0.45))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(cellShape)
            .overlay(cellShape.stroke(selected ? Theme.ink : Color.clear, lineWidth: 4 * k))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(unlocked ? String(format: L("dex_character"), i + 1) : L("dex_locked"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
