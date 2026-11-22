//
//  Narrow.swift
//  chalkdrop
//
//  스플릿 뷰처럼 세로로 긴 창에서 쓰는 좁은 화면용 도구.
//  넓은 화면은 피그마(1194 × 834) 그대로, 좁은 화면은 실제 크기로 위에서 아래로 쌓아요.
//

import SwiftUI

extension DS {
    /// 창이 기준 화면(1194 × 834)보다 가로로 좁아졌는지.
    /// 좁아지면 화면 전체를 줄이는 대신, 실제 크기 그대로 너비에 맞춰 다시 배치하는 화면을 써요.
    /// (가로가 10% 넘게 모자랄 때부터. 아이패드 전체 화면은 어느 기종이든 넓은 쪽이에요.)
    static func isNarrow(_ size: CGSize) -> Bool {
        size.width / width < size.height / height * 0.9
    }
}

/// 창이 가로로 넉넉하면 `wide`, 가로가 좁아지면 `narrow` 를 보여 줘요.
struct Adaptive<Wide: View, Narrow: View>: View {
    @ViewBuilder var wide: () -> Wide
    @ViewBuilder var narrow: (CGSize) -> Narrow

    var body: some View {
        GeometryReader { geo in
            if DS.isNarrow(geo.size) {
                narrow(geo.size)
            } else {
                wide()
            }
        }
    }
}

extension Text {
    /// 좁은 화면용 글자: 길면 다음 줄로 넘어가요.
    func dsWrap(_ size: CGFloat, _ weight: Font.Weight = .regular, _ color: Color = .black) -> some View {
        self.font(.system(size: size, weight: weight))
            .tracking(-size * 0.01)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// 창 왼쪽 위의 창 조절 버튼(빨강 · 노랑 · 초록)에 가려지지 않게 위 막대를 그 오른쪽으로 좁혀요.
    func avoidsWindowControls() -> some View {
        containerCornerOffset(.leading, sizeToFit: true)
    }

    /// 크기가 정해진(w × h) 조각을 `width` 너비에 맞게 통째로 줄이거나 늘려요.
    func scaledBox(_ w: CGFloat, _ h: CGFloat, to width: CGFloat) -> some View {
        let scale = width / w
        return frame(width: w, height: h, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: w * scale, height: h * scale, alignment: .topLeading)
    }
}

/// 좁은 화면 한 장: 위 막대 + 스크롤되는 내용 + 아래 막대
struct NarrowPage<Trailing: View, Content: View, Bottom: View>: View {
    var backTitle: String? = nil
    var barTitle = ""
    var onBack: () -> Void = {}
    var title: String? = nil
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(barTitle).ds(17, .bold)
                HStack {
                    if let backTitle {
                        Button(action: onBack) {
                            HStack(spacing: 2) {
                                Image("chevron-back-24")
                                Text(backTitle).ds(17, .medium)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    trailing
                }
                .padding(.leading, 12)
                .padding(.trailing, 20)
                .avoidsWindowControls()
            }
            .frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if title != nil || detail != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            if let title { Text(title).dsWrap(28, .bold) }
                            if let detail { Text(detail).dsWrap(15, .regular, .dsSub) }
                        }
                    }
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            bottom
        }
        .background(Color.white.ignoresSafeArea())
    }
}

/// 좁은 화면 아래 막대 (왼쪽 설명 · 오른쪽 버튼)
struct NarrowBottomBar<Trailing: View, Accessory: View>: View {
    var caption: String?
    var accessory: Accessory
    var trailing: Trailing

    init(caption: String? = nil, @ViewBuilder accessory: () -> Accessory, @ViewBuilder trailing: () -> Trailing) {
        self.caption = caption
        self.accessory = accessory()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let caption {
                Text(caption).dsWrap(15, .medium, .dsSub).lineLimit(2)
            }
            accessory
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white)
        .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
    }
}

extension NarrowBottomBar where Accessory == EmptyView {
    init(caption: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(caption: caption, accessory: { EmptyView() }, trailing: trailing)
    }
}

/// 몇 칸짜리 격자 (왼쪽 위부터 차례로)
struct NarrowGrid<Cell: View>: View {
    let count: Int
    var columns = 2
    var spacing: CGFloat = 12
    @ViewBuilder var cell: (Int) -> Cell

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<((count + columns - 1) / columns), id: \.self) { row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < count { cell(index) }
                    }
                }
            }
        }
    }
}

/// 줄이 차면 다음 줄로 넘기는 배치 (꼬리표 등)
struct Flow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = arrange(bounds.width, subviews).points
        for (index, point) in points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + rowHeight))
    }
}

/// 수업별 | 카드 모아 보기 전환 (좁은 화면용)
struct NarrowModeToggle: View {
    let mode: Int
    var onMode: (Int) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 2) {
            chip("수업별", index: 0)
            chip("카드 모아 보기", index: 1)
        }
        .padding(4)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }

    private func chip(_ title: String, index: Int) -> some View {
        let on = mode == index
        return Button { onMode(index) } label: {
            Text(title).ds(15, on ? .bold : .medium, on ? .black : .dsSub)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(on ? Color.white : Color.clear)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, x: 0, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 검은 동그란 촬영 버튼 (좁은 화면에서는 오른쪽 아래에 겹쳐 놓아요)
struct NarrowFAB: View {
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image("camera-30")
                .frame(width: 64, height: 64)
                .background(Color.black)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .zoomSource()
    }
}

/// 회색 네모 버튼 (취소 · 그대로 쓰기 등)
struct GrayButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title).ds(17, .bold)
                .padding(.horizontal, 20)
                .frame(height: 56)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
