//
//  StickerCard.swift
//  chalkdrop
//
//  v2/Sticker Card — 판서에서 찾아낸 카드 한 장
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - v2/Sticker Card

struct StickerCard: View {
    let sticker: Sticker
    var width: CGFloat = 343
    /// nil 이면 선택 표시 없음. true/false 면 오른쪽 위에 선택 동그라미를 보여 줘요.
    var selected: Bool? = nil
    var onTap: () -> Void = {}
    var onCopy: () -> Void = {}
    var onSelect: () -> Void = {}
    /// 있으면 복사 아이콘 왼쪽에 휴지통 (12 결과, #99)
    var onDelete: (() -> Void)? = nil

    @State private var handwriting: Bool
    /// 서버 손글씨 스티커 (필기만 남긴 투명 PNG)
    @State private var ink: UIImage?
    /// 붙여넣기 색 (#143). 카드가 직접 지켜봐야 색을 바꾸자마자 끌어다 놓기에도 반영돼요 (#160)
    @AppStorage(PasteColor.storageKey) private var pasteColorRaw = PasteColor.black.rawValue

    init(sticker: Sticker, width: CGFloat = 343, selected: Bool? = nil,
         onTap: @escaping () -> Void = {}, onCopy: @escaping () -> Void = {}, onSelect: @escaping () -> Void = {},
         onDelete: (() -> Void)? = nil) {
        self.sticker = sticker
        self.width = width
        self.selected = selected
        self.onSelect = onSelect
        self.onTap = onTap
        self.onCopy = onCopy
        self.onDelete = onDelete
        _handwriting = State(initialValue: sticker.handwriting)
    }

    /// 서버 스티커는 원래 잉크 색(흰 분필 등)이라, 모양만 쓰고 검정으로 칠해요.
    private func inkView(_ image: UIImage) -> some View {
        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit().foregroundStyle(.black)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("\(sticker.id)").ds(12, .bold, .white)
                    .frame(width: 24, height: 24)
                    .background(Color.black)
                    .clipShape(Circle())
                Text(sticker.title).ds(15, .bold)
                Text(sticker.kind).ds(13, .medium, .dsSub)
            }

            Group {
                if handwriting, let ink {
                    inkView(ink).frame(width: width - 40, height: 64, alignment: .leading)
                } else if handwriting, let ink = sticker.inkImage {
                    Image(ink).resizable().scaledToFit().frame(width: width - 40, height: 64, alignment: .leading)
                } else if handwriting {
                    InkCrop(sticker: sticker, width: width - 40, height: 64)
                } else {
                    // $...$ 구간은 수식으로 그려요 (#113)
                    MathText(text: sticker.text, size: 20, weight: .medium, lineGap: 20 * 1.45 - 24,
                             math: sticker.cardType != "code")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .task(id: handwriting) {
                guard handwriting, ink == nil, let id = sticker.cardID else { return }
                ink = await CardAPI.image(id)
            }

            HStack {
                HStack(spacing: 2) {
                    option("텍스트", selected: !handwriting) { handwriting = false }
                    option("손글씨", selected: handwriting) { handwriting = true }
                }
                .padding(3)
                .background(Color.black.opacity(0.05))
                .clipShape(Capsule())
                Spacer()
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.dsSub)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
                Button(action: onCopy) { Image("copy-20") }
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
        .padding(.horizontal, 20)
        .frame(width: width, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected == true ? Color.black : Color.black.opacity(0.1), lineWidth: selected == true ? 2 : 1)
        )
        // 길게 눌러 다른 앱(굿노트 등)으로 끌어다 놓을 수 있어요.
        // 끌어다 놓기는 카드가 마지막으로 그려질 때의 설정을 써서, 색은 여기(그릴 때)서 읽어 넘겨요 (#160)
        .onDrag { [pasteColor] in dragItem(pasteColor) }
        .overlay(alignment: .topTrailing) {
            if let selected {
                Button(action: onSelect) { Image(selected ? "check-on-28" : "check-off-28") }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .padding(.trailing, 14)
            }
        }
    }

    /// 끌어다 놓을 때 건네는 내용. 텍스트 보기면 글자(수식이 있으면 그린 그림), 손글씨 보기면 사진 조각.
    private var pasteColor: PasteColor { PasteColor(rawValue: pasteColorRaw) ?? .black }

    private func dragItem(_ color: PasteColor) -> NSItemProvider {
        // 굿노트로 옮긴 카드는 "옮김" 표시 (#99)
        CardAPI.markMovedQuietly([sticker])
        guard handwriting else {
            // 굿노트는 LaTeX를 그리지 못해서, 수식이 있는 카드는 화면에 보이는 모양을 그림으로 넘겨요 (#113)
            if sticker.hasMath, let image = MathText.image([sticker], width: width - 40, color: color.color) {
                return NSItemProvider(object: image)
            }
            guard color != .black else { return NSItemProvider(object: sticker.text as NSString) }
            // 붙여넣기 색 (#143): HTML → RTF → 일반 글자 순서로 등록해야 굿노트가 색 글자로 받아요
            let provider = NSItemProvider()
            for (type, data) in color.richRepresentations(sticker.text) {
                provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { done in
                    done(data, nil)
                    return nil
                }
            }
            return provider
        }
        let renderer = ImageRenderer(content: inkPiece(color.color))
        renderer.scale = 3
        #if os(iOS) || os(visionOS)
        if let image = renderer.uiImage { return NSItemProvider(object: image) }
        #elseif os(macOS)
        if let image = renderer.nsImage { return NSItemProvider(object: image) }
        #endif
        return NSItemProvider(object: sticker.text as NSString)
    }

    /// 끌어다 놓는 손글씨 크기: 사진 너비 372 기준 × 6 (예전 × 2 는 너무 작았어요), 폭은 600pt 까지 (#143)
    private var inkScale: CGFloat { min(6, 600 / max(sticker.w, 1)) }

    /// 끌어다 놓는 손글씨 조각. 서버 손글씨(투명 PNG)는 붙여넣기 색으로 칠해요.
    /// 원본 사진 조각은 사진이라 색을 바꾸지 않아요.
    @ViewBuilder
    private func inkPiece(_ color: Color) -> some View {
        if let ink {
            Image(uiImage: ink).renderingMode(.template).resizable().scaledToFit().foregroundStyle(color)
                .frame(width: sticker.w * inkScale, height: sticker.h * inkScale)
        } else if let ink = sticker.inkImage {
            Image(ink)
        } else {
            InkCrop(sticker: sticker, width: sticker.w * inkScale, height: sticker.h * inkScale)
        }
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { action() } } label: {
            Text(title).ds(12, selected ? .bold : .medium, selected ? .black : .dsSub)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(selected ? Color.white : Color.clear)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1.5, x: 0, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
