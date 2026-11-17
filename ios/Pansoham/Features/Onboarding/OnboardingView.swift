//
//  OnboardingView.swift
//  판서함
//
//  피그마 "키타가와 마린" 페이지의 01~03 온보딩 화면을 SwiftUI로 옮긴 파일.
//  사용법:  OnboardingView { /* 끝났을 때 할 일 (예: 로그인 화면으로 이동) */ }
//
 
import SwiftUI
 
// MARK: - 색 (피그마 값 그대로)
 
private extension Color {
    static let obText = Color.black                                           // #000000
    static let obSub = Color(red: 0x8B / 255, green: 0x8B / 255, blue: 0x90 / 255) // #8B8B90
    static let obAccent = Color(red: 0x33 / 255, green: 0x66 / 255, blue: 1.0)     // #3366FF
    static let obPanel = Color.black.opacity(0.04)                            // 그림 배경
}
 
// MARK: - 페이지 내용
 
private struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let message: String
}
 
private let onboardingPages: [OnboardingPage] = [
    .init(id: 0,
          title: "찍으세요.",
          message: "화면 반사와 기울기는 알아서 펴고,\n배경은 지우고 판서만 남겨요"),
    .init(id: 1,
          title: "바로 옮기세요",
          message: "스플릿 뷰에서 판서를 끌어다 놓거나\n복사해서 붙여 넣으면 끝이에요"),
    .init(id: 2,
          title: "과목별로 알아서 모여요",
          message: "에브리타임 시간표를 한 번만 올려 두면\n수업 시간에 찍은 판서가 과목 폴더로 들어가요"),
]
 
// MARK: - 온보딩 화면
 
struct OnboardingView: View {
    /// 건너뛰기 또는 시작하기를 눌렀을 때 불려요.
    var onFinish: () -> Void = {}
 
    @State private var page = 0
    @State private var width: CGFloat = 1194     // 창 너비 (좁으면 그림을 줄여요)
 
    private var isLast: Bool { page == onboardingPages.count - 1 }
 
    var body: some View {
        VStack(spacing: 0) {
            // 넘겨 보는 영역
            #if os(iOS)
            TabView(selection: $page) {
                ForEach(onboardingPages) { item in
                    pageContent(item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            #else
            // macOS에는 페이지 스타일 TabView가 없어서 현재 페이지만 보여 줘요.
            pageContent(onboardingPages[page])
                .id(page)
                .transition(.opacity)
            #endif
 
            bottomBar
        }
        .background(Color.white.ignoresSafeArea())
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, new in width = new }
        })
    }
 
    // 그림 + 제목 + 설명 + 점
    private func pageContent(_ item: OnboardingPage) -> some View {
        VStack(spacing: 0) {
            illustration(for: item.id)
                .frame(width: 640, height: 340)
                .background(Color.obPanel)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .scaledBox(640, 340, to: min(640, width - 40))
 
            Text(item.title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.85)
                .foregroundStyle(Color.obText)
                .padding(.top, 48)
 
            Text(item.message)
                .font(.system(size: 17, weight: .regular))
                .tracking(-0.17)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .foregroundStyle(Color.obSub)
                .padding(.top, 16)
 
            PageDots(count: onboardingPages.count, current: item.id)
                .padding(.top, 32)
 
            Spacer(minLength: 0)
        }
        .padding(.top, width < 700 ? 28 : 66)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
 
    @ViewBuilder
    private func illustration(for index: Int) -> some View {
        switch index {
        case 0: CaptureIllustration()
        case 1: MoveIllustration()
        default: FoldersIllustration()
        }
    }
 
    // 아래 막대: 건너뛰기 / 다음 · 시작하기
    private var bottomBar: some View {
        HStack {
            if !isLast {
                Button("건너뛰기") { onFinish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.17)
                    .foregroundStyle(Color.obSub)
            }
 
            Spacer()
 
            Button {
                if isLast {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                }
            } label: {
                Text(isLast ? "시작하기" : "다음")
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.17)
                    .foregroundStyle(.white)
                    .frame(width: width < 440 ? 160 : 220, height: 56)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, width < 700 ? 20 : 48)
        .padding(.top, 20)
        .padding(.bottom, 28)
    }
}
 
// MARK: - 페이지 점
 
private struct PageDots: View {
    let count: Int
    let current: Int
 
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.black : Color.black.opacity(0.15))
                    .frame(width: i == current ? 20 : 6, height: 6)
            }
        }
    }
}
 
// MARK: - 그림 도우미
 
private extension View {
    /// 피그마 좌표(왼쪽 위 기준)에 그대로 놓기
    func place(x: CGFloat, y: CGFloat) -> some View {
        self.offset(x: x, y: y)
    }
}
 
/// 글씨 줄 (가로 막대)
private struct Bar: View {
    let width: CGFloat
    var height: CGFloat = 6
    var color: Color = .black
 
    var body: some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}
 
// MARK: - 그림 1: 찍으세요
 
private struct CaptureIllustration: View {
    // 피그마 타임라인: 2초 되풀이
    var body: some View { Motion(loop: 2) { t in content(t) } }

    private func content(_ t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            // 검은 화면(칠판)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black)
                Bar(width: 180, height: 8, color: .white.opacity(0.85)).place(x: 40, y: 50)
                Bar(width: 240, height: 8, color: .white.opacity(0.85)).place(x: 40, y: 86)
                Bar(width: 140, height: 8, color: .white.opacity(0.85)).place(x: 40, y: 122)
                Bar(width: 120, height: 8, color: .white.opacity(0.85)).place(x: 200, y: 150)
            }
            .frame(width: 380, height: 220, alignment: .topLeading)
            .place(x: 130, y: 60)
 
            // 파란 모서리 표시
            CornerBrackets(length: 32)
                .stroke(Color.obAccent, style: StrokeStyle(lineWidth: 4, lineCap: .square))
                .frame(width: 416, height: 256)
                .scaleEffect(tween(t, 1.15, 1, 0.2, 0.9, .spring))
                .opacity(tween(t, 0, 1, 0.2, 0.5, .inOut))
                .place(x: 112, y: 42)
        }
        .frame(width: 640, height: 340, alignment: .topLeading)
    }
}
 
/// 네 모서리에 ㄱ자 표시를 그려요.
private struct CornerBrackets: Shape {
    let length: CGFloat
 
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length
        // 왼쪽 위
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // 오른쪽 위
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // 오른쪽 아래
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // 왼쪽 아래
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}
 
// MARK: - 그림 2: 바로 옮기세요
 
private struct MoveIllustration: View {
    // 피그마 타임라인: 2초 되풀이
    var body: some View { Motion(loop: 2) { t in content(t) } }

    private func content(_ t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            // 왼쪽: 판서함
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                miniTitle("판서함").place(x: 18, y: 16)
                noteBlock(first: 150, second: 90).place(x: 18, y: 48)
                noteBlock(first: 120, second: 90).place(x: 18, y: 136)
            }
            .frame(width: 250, height: 260, alignment: .topLeading)
            .place(x: 48, y: 40)
 
            // 오른쪽: 굿노트
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                miniTitle("굿노트").place(x: 18, y: 16)
                ForEach(0..<6, id: \.self) { i in
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 242, height: 1)
                        .place(x: 18, y: 60 + CGFloat(i) * 32)
                }
            }
            .frame(width: 278, height: 260, alignment: .topLeading)
            .place(x: 314, y: 40)
 
            // 끌려가는 판서 카드
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                Bar(width: 150).place(x: 16, y: 24)
                Bar(width: 90).place(x: 16, y: 42)
            }
            .frame(width: 200, height: 74, alignment: .topLeading)
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 12)
            .offset(x: tween(t, -165, 0, 0.2, 1.2, .inOut), y: tween(t, -102, 0, 0.2, 1.2, .inOut))
            .place(x: 230, y: 150)
        }
        .frame(width: 640, height: 340, alignment: .topLeading)
    }
 
    private func miniTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .tracking(-0.13)
            .foregroundStyle(Color.obText)
    }
 
    private func noteBlock(first: CGFloat, second: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.obPanel)
            Bar(width: first).place(x: 16, y: 24)
            Bar(width: second).place(x: 16, y: 42)
        }
        .frame(width: 214, height: 74, alignment: .topLeading)
    }
}
 
// MARK: - 그림 3: 과목별로 알아서 모여요
 
private struct FoldersIllustration: View {
    private let rows: [(name: String, count: String)] = [
        ("자료구조", "12장"),
        ("컴퓨터구조", "8장"),
        ("이산수학", "3장"),
    ]
 
    // 피그마 타임라인: 2초 되풀이
 
    var body: some View { Motion(loop: 2) { t in content(t) } }

 
    private func content(_ t: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.obText)
                    Spacer()
                    Text(row.count)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.obSub)
                }
                .tracking(-0.17)
                .frame(height: 53)
                .opacity(tween(t, 0, 1, 0.2 + 0.15 * Double(index), 0.65 + 0.15 * Double(index)))
                .offset(y: tween(t, 12, 0, 0.2 + 0.15 * Double(index), 0.65 + 0.15 * Double(index)))
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 {
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(width: 380)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(width: 640, height: 340)
    }
}
 
// MARK: - 미리보기
 
#if os(iOS)
#Preview("온보딩", traits: .landscapeLeft) {
    OnboardingView()
}
#else
#Preview("온보딩") {
    OnboardingView()
}
#endif
