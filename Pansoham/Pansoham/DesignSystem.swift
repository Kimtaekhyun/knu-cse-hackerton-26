//
//  DesignSystem.swift
//  판서함
//
//  피그마 "키타가와 마린" 페이지의 공통 색 · 글자 · 버튼 · 카드.
//  모든 화면은 피그마 기준 크기(1194 × 834, 아이패드 11형 가로)로 그리고
//  DesignCanvas 가 실제 화면 크기에 맞게 줄이거나 늘려요.
//

import SwiftUI

// MARK: - 색 (피그마 값 그대로)

extension Color {
    static let dsSub = Color(red: 0x8B / 255, green: 0x8B / 255, blue: 0x90 / 255)      // #8B8B90
    static let dsBlue = Color(red: 0x33 / 255, green: 0x66 / 255, blue: 1.0)            // #3366FF
    static let dsBlueSoft = Color(red: 0xE3 / 255, green: 0xEB / 255, blue: 1.0)        // #E3EBFF
    static let dsKakao = Color(red: 0xFB / 255, green: 0xEB / 255, blue: 0x05 / 255)    // #FBEB05
    static let dsPanel = Color.black.opacity(0.04)
    static let dsLine = Color.black.opacity(0.08)
}

// MARK: - 글자

extension Text {
    /// 피그마 글자 스타일. 자간은 큰 제목 -2.5%, 나머지 -1%.
    /// `line` 은 피그마 줄 높이 배수(예: 1.55).
    func ds(_ size: CGFloat,
            _ weight: Font.Weight = .regular,
            _ color: Color = .black,
            line: CGFloat? = nil) -> some View {
        self.font(.system(size: size, weight: weight))
            .tracking(-size * (size >= 34 ? 0.025 : 0.01))
            .foregroundStyle(color)
            .lineSpacing(line.map { max(0, size * $0 - size * 1.2) } ?? 0)
            .fixedSize()
    }
}

// MARK: - 기준 캔버스

enum DS {
    static let width: CGFloat = 1194
    static let height: CGFloat = 834
}

/// 피그마 프레임(1194 × 834)을 화면에 맞춰 보여 주는 틀.
struct DesignCanvas<Content: View>: View {
    var background: Color = .white
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / DS.width, geo.size.height / DS.height)
            ZStack(alignment: .topLeading) {
                background
                content
            }
            .frame(width: DS.width, height: DS.height, alignment: .topLeading)
            .clipped()
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(background.ignoresSafeArea())
        .ignoresSafeArea()
    }
}

extension View {
    /// 피그마 좌표(왼쪽 위 기준)에 놓기
    func at(_ x: CGFloat, _ y: CGFloat) -> some View {
        offset(x: x, y: y)
    }
}

// MARK: - 버튼

/// v2/Button/Primary — 검은 버튼
struct PrimaryButton: View {
    let title: String
    var width: CGFloat = 220
    var enabled = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title).ds(17, .bold, .white)
                .frame(width: width, height: 56)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(enabled ? 1 : 0.15)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// v2/Button/Secondary — 흰 테두리 버튼
struct SecondaryButton: View {
    let title: String
    var width: CGFloat = 220
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title).ds(16, .bold)
                .frame(width: width, height: 52)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 위 막대 (뒤로 · 제목 · 오른쪽 글자)

struct NavBar<Trailing: View>: View {
    let backTitle: String
    let title: String
    var onBack: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title).ds(17, .bold)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image("chevron-back-24")
                        Text(backTitle).ds(17, .medium)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                trailing
            }
            .padding(.leading, 36)
            .padding(.trailing, 48)
        }
        .frame(width: DS.width, height: 56)
        .at(0, 24)
    }
}

extension NavBar where Trailing == EmptyView {
    init(backTitle: String, title: String, onBack: @escaping () -> Void = {}) {
        self.init(backTitle: backTitle, title: title, onBack: onBack) { EmptyView() }
    }
}

// MARK: - 아래 막대 (왼쪽 설명 · 오른쪽 버튼)

struct BottomBar<Trailing: View>: View {
    let caption: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(caption).ds(17, .medium, .dsSub)
            Spacer()
            trailing
        }
        .padding(.horizontal, 48)
        .frame(width: DS.width, height: 104)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.dsLine).frame(height: 1)
        }
        .at(0, 730)
    }
}

// MARK: - 과목 폴더 카드 (v2/Subject Card)

struct SubjectCard: View {
    enum Style { case blue, gray, dashed }

    let name: String
    let detail: String
    let count: Int
    var style: Style = .gray
    /// 236(메인) 또는 260(학기 화면). 폴더 그림이 너비마다 따로 있어요.
    var width: CGFloat = 236
    /// 숫자 대신 보여 줄 글자 (예: "+")
    var symbol: String? = nil
    var action: () -> Void = {}

    private var backgroundName: String {
        let base: String
        switch style {
        case .blue: base = "folder-blue"
        case .gray: base = "folder-gray"
        case .dashed: base = "folder-dashed"
        }
        return width == 260 ? base + "-260" : base
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let symbol {
                        Text(symbol).ds(34, .bold, .dsSub)
                    } else {
                        Text("\(count)").ds(34, .bold, count == 0 ? .black.opacity(0.2) : .black)
                        Text("장").ds(15, .medium, .dsSub)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).ds(17, .bold)
                    Text(detail).ds(13, .regular, .dsSub)
                }
            }
            .padding(.top, 34)
            .padding(.bottom, 18)
            .padding(.horizontal, 20)
            .frame(width: width, height: 166, alignment: .topLeading)
            .background(
                Image(backgroundName).resizable().frame(width: width, height: 166)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 판서 사진 잘라 보여 주기

/// 피그마처럼 사진 한 장의 일부만 잘라 보여 줘요.
/// `scale` 은 틀 대비 사진 크기, `x`·`y` 는 틀 대비 이동 비율.
struct BoardPhoto: View {
    var name = "board-photo"
    let width: CGFloat
    let height: CGFloat
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var x: CGFloat = 0
    var y: CGFloat = 0
    var radius: CGFloat = 8

    var body: some View {
        Image(name)
            .resizable()
            .frame(width: width * scaleX, height: height * scaleY)
            .offset(x: width * x, y: height * y)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - 화면 이동

enum Screen: String, Hashable, CaseIterable {
    case onboarding, login, timetableUpload, timetableConfirm
    case homeFirst, home
    case capture, processing, captureError
    case result, copied, splitView, cardDetail
    case subjectLessons, subjectCards, subjectEmpty
    case unsorted, unsortedMove
    case allSemesters, pastSemester, account
    case pending
}

@Observable
final class Router {
    var stack: [Screen] = [.onboarding]
    /// 시간표 업로드(05)에서 고른 캡처. 시간표 확인(06)에서 원본으로 보여 줘요.
    var timetableImage: UIImage?

    init() {
        // 특정 화면부터 열어 보기: 실행 인자에 `-startScreen home` 처럼 화면 이름을 넣어요.
        if let name = UserDefaults.standard.string(forKey: "startScreen"), let screen = Screen(rawValue: name) {
            stack = [screen]
        }
    }

    var current: Screen { stack.last ?? .onboarding }

    func push(_ screen: Screen) { stack.append(screen) }
    func pop() {
        if stack.count > 1 { stack.removeLast() } else if current != .onboarding { stack = [.home] }
    }
    /// 지금 화면을 다른 화면으로 바꾸기 (뒤로 가도 돌아오지 않아요)
    func replace(_ screen: Screen) {
        if !stack.isEmpty { stack.removeLast() }
        stack.append(screen)
    }
    /// 처음부터 다시 쌓기
    func reset(to screen: Screen) { stack = [screen] }
    /// 쌓인 화면 중 가장 가까운 `screen` 까지 돌아가기. 없으면 새로 시작.
    func popTo(_ screen: Screen) {
        if let i = stack.lastIndex(of: screen) { stack = Array(stack[...i]) } else { stack = [screen] }
    }
}
