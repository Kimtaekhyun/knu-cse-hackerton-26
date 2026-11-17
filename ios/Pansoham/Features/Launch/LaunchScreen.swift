//
//  LaunchScreen.swift
//  chalkdrop
//
//  앱을 켤 때 잠깐 보여 주는 화면. 로고의 파란 선이 좌우로 훑고 지나가며
//  어두운 면(판서)과 밝은 면(정리된 노트)이 바뀌는 모습을 보여 줘요.

import SwiftUI

struct LaunchScreen: View {
    var onFinish: () -> Void

    @State private var start = Date()

    // 타임라인(초): 0.25~0.85 오른쪽 → 0.85~1.55 왼쪽 → 1.55~2.0 가운데로 돌아와요.
    // 1.6초부터 이름이 떠오르고, 2.5초에 화면을 닫아요.
    private let total = 2.5

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            VStack(spacing: 28) {
                LogoMark(split: split(t))
                    .frame(width: 220, height: 220 * 608 / 664)
                    .scaleEffect(tween(t, 0.92, 1, 0, 0.5, .out))
                    .opacity(tween(t, 0, 1, 0, 0.3, .out))
                Text("chalkdrop").ds(30, .bold)
                    .opacity(tween(t, 0, 1, 1.6, 2.0, .out))
                    .offset(y: tween(t, 8, 0, 1.6, 2.0, .out))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
        }
        .task {
            start = Date()
            try? await Task.sleep(for: .seconds(total))
            onFinish()
        }
    }

    /// 파란 선의 x 위치 (로고 1024 캔버스 기준, 가운데 = 512)
    private func split(_ t: Double) -> CGFloat {
        let center = 512.0, right = 760.0, left = 264.0
        if t < 0.85 { return tween(t, center, right, 0.25, 0.85, .inOut) }
        if t < 1.55 { return tween(t, right, left, 0.85, 1.55, .inOut) }
        return tween(t, left, center, 1.55, 2.0, .inOut)
    }
}

/// 새 로고를 그대로 그린 도형. split 에 따라 파란 선과 어두운 면이 함께 움직여요.
/// 좌표는 원본 로고(1024×1024)에서 가져왔고, 그림 영역은 x 180~844, y 208~816 이에요.
struct LogoMark: View {
    var split: CGFloat = 512

    private static let ink = Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x13 / 255)
    private static let slate = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2C / 255)

    // 줄 세 개씩 (x, 길이, y). 두께 32, 끝이 둥글어요.
    private static let lines: [(CGFloat, CGFloat, CGFloat)] = [
        (264, 184, 392), (264, 144, 496), (264, 168, 600),
        (576, 184, 392), (576, 144, 496), (576, 168, 600),
    ]

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 664
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: (x - 180) * s, y: (y - 208) * s, width: w * s, height: h * s)
            }
            func round(_ rect: CGRect, _ radius: CGFloat) -> Path {
                Path(roundedRect: rect, cornerRadius: radius * s, style: .continuous)
            }
            let inner = round(r(204, 284, 616, 456), 60)

            // 테두리 + 밝은 면 + 검은 줄
            ctx.fill(round(r(180, 260, 664, 504), 84), with: .color(Self.ink))
            ctx.fill(inner, with: .color(.white))
            for (x, w, y) in Self.lines {
                ctx.fill(round(r(x, y, w, 32), 16), with: .color(Self.ink))
            }

            // 파란 선 왼쪽은 어두운 면 + 흰 줄
            ctx.drawLayer { dark in
                dark.clip(to: Path(r(180, 208, split - 180, 608)))
                dark.fill(inner, with: .color(Self.slate))
                for (x, w, y) in Self.lines {
                    dark.fill(round(r(x, y, w, 32), 16), with: .color(.white))
                }
            }

            // 파란 선
            ctx.fill(round(r(split - 16, 208, 32, 608), 16), with: .color(.dsBlue))
        }
        .accessibilityLabel("chalkdrop 로고")
    }
}

#Preview {
    LaunchScreen {}
}
