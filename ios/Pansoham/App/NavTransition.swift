//
//  NavTransition.swift
//  chalkdrop
//
//  화면 전환 애니메이션. 아이패드 기본 앱처럼
//  앞으로 가면 새 화면이 오른쪽에서 밀고 들어오고, 뒤로 가면 이전 화면이 왼쪽에서 돌아와요.
//  촬영 화면은 누른 촬영 버튼에서 커지며 열리고, 닫을 때 그 자리로 줄어들어요.
//

import SwiftUI

struct NavTransition: Transition {
    /// 방향은 화면이 사라지는 순간에 읽어야 해서 값 대신 Router 를 들고 있어요.
    /// (값으로 들고 있으면 사라지는 화면은 이전 이동의 방향으로 움직여요)
    let router: Router

    func body(content: Content, phase: TransitionPhase) -> some View {
        let direction = router.direction
        let anchor = router.zoomAnchor
        let shift = Self.shift(direction, phase)
        let behind = Self.isBehind(direction, phase)

        content
            .visualEffect { view, proxy in view.offset(x: shift * proxy.size.width) }
            .scaleEffect(Self.scale(direction, phase), anchor: anchor)
            .opacity(Self.opacity(direction, phase))
            // 뒤에 깔리는 화면은 살짝 어둡게
            .overlay { Color.black.opacity(behind ? 0.08 : 0).allowsHitTesting(false) }
            .shadow(color: .black.opacity(Self.isFront(direction, phase) ? 0.12 : 0), radius: 24)
    }

    /// 가로 이동 (화면 너비 비율)
    private static func shift(_ direction: NavDirection, _ phase: TransitionPhase) -> CGFloat {
        switch (direction, phase) {
        case (.forward, .willAppear), (.back, .didDisappear): 1
        case (.forward, .didDisappear), (.back, .willAppear): -0.3
        default: 0
        }
    }

    private static func scale(_ direction: NavDirection, _ phase: TransitionPhase) -> CGFloat {
        switch (direction, phase) {
        case (.zoomIn, .willAppear), (.zoomOut, .didDisappear): 0.05
        case (.zoomIn, .didDisappear), (.zoomOut, .willAppear): 0.96
        default: 1
        }
    }

    private static func opacity(_ direction: NavDirection, _ phase: TransitionPhase) -> Double {
        switch (direction, phase) {
        case (.fade, .willAppear), (.fade, .didDisappear): 0
        case (.zoomIn, .willAppear), (.zoomOut, .didDisappear): 0
        default: 1
        }
    }

    /// 아래에 깔려 있는 화면인지
    private static func isBehind(_ direction: NavDirection, _ phase: TransitionPhase) -> Bool {
        switch (direction, phase) {
        case (.forward, .didDisappear), (.back, .willAppear),
             (.zoomIn, .didDisappear), (.zoomOut, .willAppear): true
        default: false
        }
    }

    /// 위에서 움직이는 화면인지 (그림자를 줘요)
    private static func isFront(_ direction: NavDirection, _ phase: TransitionPhase) -> Bool {
        switch (direction, phase) {
        case (.forward, .willAppear), (.back, .didDisappear): true
        default: false
        }
    }
}

extension NavDirection {
    var animation: Animation {
        switch self {
        case .forward, .back: .spring(duration: 0.42, bounce: 0)
        case .fade: .easeInOut(duration: 0.25)
        case .zoomIn: .spring(duration: 0.45, bounce: 0.12)
        case .zoomOut: .spring(duration: 0.38, bounce: 0)
        }
    }

    /// 뒤로 가는 이동이면 새 화면을 사라지는 화면 아래에 그려요.
    var drawsBelow: Bool { self == .back || self == .zoomOut }
}

extension View {
    /// 촬영 버튼에 붙여요. 손가락이 닿은 자리를 촬영 화면이 커져 나오는 기준점으로 기억해요.
    func zoomSource() -> some View {
        modifier(ZoomSource())
    }
}

private struct ZoomSource: ViewModifier {
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                router.zoomAnchor = router.anchor(for: value.startLocation)
            }
        )
    }
}
