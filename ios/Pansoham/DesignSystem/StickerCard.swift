//
//  StickerCard.swift
//  chalkdrop
//
//  v2/Sticker Card — 판서에서 찾아낸 카드 한 장
//

import SwiftUI

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
                    Text(sticker.text)
                        .font(.system(size: 20, weight: .medium))
                        .tracking(-0.2)
                        .lineSpacing(20 * 1.45 - 24)
                        .foregroundStyle(.black)
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
        .onDrag { dragItem() }
        .overlay(alignment: .topTrailing) {
            if let selected {
                Button(action: onSelect) { Image(selected ? "check-on-28" : "check-off-28") }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .padding(.trailing, 14)
            }
        }
    }

    /// 끌어다 놓을 때 건네는 내용. 텍스트 보기면 글자, 손글씨 보기면 사진 조각.
    private func dragItem() -> NSItemProvider {
        // 굿노트로 옮긴 카드는 "옮김" 표시 (#99)
        CardAPI.markMovedQuietly([sticker])
        guard handwriting else { return NSItemProvider(object: sticker.text as NSString) }
        let renderer = ImageRenderer(content: inkPiece)
        renderer.scale = 3
        #if os(iOS) || os(visionOS)
        if let image = renderer.uiImage { return NSItemProvider(object: image) }
        #elseif os(macOS)
        if let image = renderer.nsImage { return NSItemProvider(object: image) }
        #endif
        return NSItemProvider(object: sticker.text as NSString)
    }

    /// 원본 사진에서 이 카드 자리 전체를 잘라 낸 조각
    @ViewBuilder
    private var inkPiece: some View {
        if let ink {
            inkView(ink).frame(width: sticker.w * 2, height: sticker.h * 2)
        } else if let ink = sticker.inkImage {
            Image(ink)
        } else {
            InkCrop(sticker: sticker, width: sticker.w * 2, height: sticker.h * 2)
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
