//
//  CardDetailScreen.swift
//  chalkdrop
//
//  17 카드 상세·수정
//

import SwiftUI

// MARK: - 17 카드 상세·수정

struct CardDetailScreen: View {
    @Environment(Router.self) private var router

    private static let originalTitle = "극한 계산"
    private static let originalLatex = #"\lim_{x\to\infty}\frac{\ln x}{x} = \lim_{x\to\infty}\frac{1}{x} = 0"#

    @State private var title = CardDetailScreen.originalTitle
    @State private var kind = 1          // 0 텍스트, 1 수식, 2 코드
    @State private var latex = CardDetailScreen.originalLatex
    @State private var confirmingDelete = false
    @State private var saved = false

    private let kinds = ["텍스트", "수식", "코드"]

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .overlay(alignment: .bottom) {
                if saved {
                    savedToast
                        .padding(.bottom, 120)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert("카드를 삭제할까요?", isPresented: $confirmingDelete) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) { router.pop() }
            } message: {
                Text("삭제한 카드는 되돌릴 수 없어요.")
            }
    }

    /// 결과 화면 "카드 N개를 복사했어요" 알림과 같은 모양
    private var savedToast: some View {
        HStack(spacing: 12) {
            Image("check-circle-24")
            Text("카드를 저장했어요").ds(15, .bold, .white)
        }
        .padding(.leading, 18)
        .padding(.trailing, 24)
        .padding(.vertical, 14)
        .background(Color.black)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 12)
    }

    /// 저장 알림을 잠깐 띄운 뒤 결과 화면으로 돌아가요. (실제 저장은 데이터 연결 때)
    private func save() {
        guard !saved else { return }
        withAnimation(.easeOut(duration: 0.3)) { saved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            router.pop()
        }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "결과", title: "카드 수정", onBack: { router.pop() }) {
                Button { confirmingDelete = true } label: { Text("삭제").ds(17, .medium, .dsSub) }
                    .buttonStyle(.plain)
            }

            // 원본에서 가져온 부분
            VStack(alignment: .leading, spacing: 12) {
                label("원본에서 가져온 부분")
                ZStack(alignment: .topLeading) {
                    Color.dsPanel
                    ZStack(alignment: .topLeading) {
                        Image("board-photo")
                            .resizable()
                            .frame(width: 452, height: 252 * 1.3459)
                            .offset(y: -252 * 0.0673)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.dsBlue.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.dsBlue, lineWidth: 2.5))
                            .frame(width: 194.36, height: 122)
                            .at(248.6, 27)
                    }
                    .frame(width: 452, height: 252, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .at(24, 24)
                }
                .frame(width: 500, height: 300, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Color.clear.frame(width: 1, height: 4)
                Text("AI가 읽은 내용이에요. 틀린 부분만 고치면 돼요.").ds(15, .regular, .dsSub)
            }
            .at(48, 104)

            // 고치는 칸
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    label("제목")
                    field($title)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(width: 550, alignment: .leading)
                        .background(Color.dsPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("종류")
                    HStack(spacing: 2) {
                        ForEach(Array(kinds.enumerated()), id: \.offset) { index, name in
                            let on = kind == index
                            Button { withAnimation(.easeInOut(duration: 0.15)) { kind = index } } label: {
                                Text(name).ds(15, on ? .bold : .medium, on ? .black : .dsSub)
                                    .padding(.vertical, 10)
                                    .frame(width: 180)
                                    .background(on ? Color.white : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, x: 0, y: 1)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("내용 (LaTeX)")
                    field($latex)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(width: 550, height: 96, alignment: .topLeading)
                        .background(Color.dsPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("미리보기")
                    Text("lim ln x / x = lim 1 / x = 0").ds(28, .regular)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 28)
                        .frame(width: 550)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
                }
            }
            .at(596, 104)

            // 아래 막대
            HStack {
                Button {
                    title = Self.originalTitle
                    latex = Self.originalLatex
                    kind = 1
                } label: {
                    Text("원래대로 되돌리기").ds(17, .medium, .dsSub)
                }
                .buttonStyle(.plain)
                Spacer()
                PrimaryButton(title: "저장") { save() }
            }
            .padding(.horizontal, 48)
            .frame(width: DS.width, height: 104)
            .background(Color.white)
            .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
            .at(0, 730)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).ds(13, .bold, .dsSub)
    }

    private func field(_ text: Binding<String>, axis: Axis = .horizontal) -> some View {
        TextField("", text: text, axis: axis)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .tracking(-0.17)
            .foregroundStyle(.black)
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension CardDetailScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = size.width - 40
        let segment = (inner - 8 - 4) / 3
        return NarrowPage(backTitle: "결과", barTitle: "카드 수정", onBack: { router.pop() },
                          trailing: {
            Button { confirmingDelete = true } label: { Text("삭제").ds(17, .medium, .dsSub) }
                .buttonStyle(.plain)
        }, content: {
            // 원본에서 가져온 부분
            VStack(alignment: .leading, spacing: 8) {
                label("원본에서 가져온 부분")
                ZStack(alignment: .topLeading) {
                    Color.dsPanel
                    ZStack(alignment: .topLeading) {
                        Image("board-photo")
                            .resizable()
                            .frame(width: 452, height: 252 * 1.3459)
                            .offset(y: -252 * 0.0673)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.dsBlue.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.dsBlue, lineWidth: 2.5))
                            .frame(width: 194.36, height: 122)
                            .at(248.6, 27)
                    }
                    .frame(width: 452, height: 252, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .at(24, 24)
                }
                .frame(width: 500, height: 300, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaledBox(500, 300, to: min(500, inner))
                Text("AI가 읽은 내용이에요. 틀린 부분만 고치면 돼요.").dsWrap(14, .regular, .dsSub)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("제목")
                field($title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(width: inner, alignment: .leading)
                    .background(Color.dsPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                label("종류")
                HStack(spacing: 2) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { index, name in
                        let on = kind == index
                        Button { withAnimation(.easeInOut(duration: 0.15)) { kind = index } } label: {
                            Text(name).ds(15, on ? .bold : .medium, on ? .black : .dsSub)
                                .padding(.vertical, 10)
                                .frame(width: segment)
                                .background(on ? Color.white : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, x: 0, y: 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                label("내용 (LaTeX)")
                field($latex, axis: .vertical)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(width: inner, height: 96, alignment: .topLeading)
                    .background(Color.dsPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                label("미리보기")
                Text("lim ln x / x = lim 1 / x = 0")
                    .font(.system(size: 26))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(width: inner)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
            }
        }, bottom: {
            HStack {
                Button {
                    title = Self.originalTitle
                    latex = Self.originalLatex
                    kind = 1
                } label: { Text("원래대로 되돌리기").ds(15, .medium, .dsSub) }
                .buttonStyle(.plain)
                Spacer()
                PrimaryButton(title: "저장", width: inner < 440 ? 130 : 200) { save() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
        })
    }
}
