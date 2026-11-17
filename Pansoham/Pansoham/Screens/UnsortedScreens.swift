//
//  UnsortedScreens.swift
//  판서함
//
//  19 미분류함 · 20 미분류함 · 과목으로 옮기기
//

import SwiftUI

struct UnsortedScreen: View {
    /// true 면 처음부터 "과목으로 옮기기" 창을 띄워요 (20 화면).
    var startsMoving = false

    @Environment(Router.self) private var router

    private struct Item: Identifiable, Equatable {
        let id: Int
        let date: String
        let shortDate: String
        let cards: Int
        let detail: String
        let x: CGFloat, y: CGFloat
    }

    @State private var items: [Item] = [
        .init(id: 0, date: "11월 16일 (일) 21:14", shortDate: "11월 16일 21:14", cards: 4,
              detail: "카드 4개 · 스택의 연산, 큐의 연산 외 2개", x: -0.6333, y: -0.8443),
        .init(id: 1, date: "11월 15일 (토) 14:02", shortDate: "11월 15일 14:02", cards: 2,
              detail: "카드 2개 · 해시 함수, 충돌 처리", x: -0.0333, y: -0.1876),
        .init(id: 2, date: "11월 12일 (수) 19:40", shortDate: "11월 12일 19:40", cards: 6,
              detail: "카드 6개 · 프로세스 상태, 문맥 교환 외 4개", x: -0.3333, y: -0.5629),
    ]
    @State private var moving: Item?
    @State private var target = "자료구조"

    private let subjects = SampleData.timetable.map(\.name)

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            FolderNavBar(onBack: { router.popTo(.home) })
            SubjectHeader(name: "미분류함",
                          detail: "시간표 밖에서 찍은 판서 \(items.count)장 · 과목으로 옮겨 정리하세요")

            // 미분류 목록
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(spacing: 20) {
                        LessonThumb(x: item.x, y: item.y)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.date).ds(20, .bold)
                            Text(item.detail).ds(15, .regular, .dsSub)
                        }
                        Spacer(minLength: 0)
                        Button {
                            target = "자료구조"
                            withAnimation(.easeOut(duration: 0.3)) { moving = item }
                        } label: {
                            Text("과목으로 옮기기").ds(16, .bold)
                                .frame(width: 180, height: 48)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 20)
                    .frame(width: 1098)
                    .overlay(alignment: .bottom) {
                        if item != items.last { Rectangle().fill(Color.dsLine).frame(height: 1) }
                    }
                }
            }
            .at(48, 196)

            CaptureFAB { router.push(.capture) }

            if let moving {
                // 어둡게 깔기
                Color.black.opacity(0.4)
                    .frame(width: DS.width, height: DS.height)
                    .onTapGesture { close() }
                    .transition(.opacity)

                moveDialog(moving)
                    .at(357, 192)
                    .transition(.opacity.combined(with: .offset(y: 40)).animation(.easeOut(duration: 0.4).delay(0.05)))
            }
        }
        .onAppear {
            if startsMoving { withAnimation(.easeOut(duration: 0.3)) { moving = items.first } }
        }
    }

    /// 과목 선택 창
    private func moveDialog(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("어느 과목으로 옮길까요?").ds(22, .bold)
            Color.clear.frame(width: 1, height: 6)
            Text("\(item.shortDate) · 카드 \(item.cards)개").ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 16)

            ForEach(subjects, id: \.self) { subject in
                let on = target == subject
                Button { target = subject } label: {
                    HStack {
                        Text(subject).ds(17, on ? .bold : .medium)
                        Spacer()
                        Image(on ? "radio-on-24" : "radio-off-24")
                    }
                    .padding(.vertical, 14)
                    .frame(width: 424)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Color.clear.frame(width: 1, height: 16)
            HStack(spacing: 10) {
                Button { close() } label: {
                    Text("취소").ds(17, .bold)
                        .frame(width: 120, height: 56)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                PrimaryButton(title: "\(target)로 옮기기", width: 294) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        items.removeAll { $0.id == item.id }
                        moving = nil
                    }
                }
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 24)
        .padding(.horizontal, 28)
        .frame(width: 480, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { moving = nil }
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension UnsortedScreen {
    func narrow(_ size: CGSize) -> some View {
        NarrowPage(backTitle: "판서함", onBack: { router.popTo(.home) },
                   title: "미분류함",
                   detail: "시간표 밖에서 찍은 판서 \(items.count)장 · 과목으로 옮겨 정리하세요",
                   trailing: {
            HStack(spacing: 20) {
                Image("search-24")
                Image("more-24")
            }
        }, content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        LessonThumb(x: item.x, y: item.y).scaledBox(168, 112, to: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.date).dsWrap(17, .bold)
                            Text(item.detail).dsWrap(14, .regular, .dsSub)
                            Button {
                                target = "자료구조"
                                withAnimation(.easeOut(duration: 0.3)) { moving = item }
                            } label: {
                                Text("과목으로 옮기기").ds(14, .bold)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 18)
                    .overlay(alignment: .bottom) {
                        if item != items.last { Rectangle().fill(Color.dsLine).frame(height: 1) }
                    }
                }
            }
            .padding(.bottom, 80)
        }, bottom: { EmptyView() })
        .overlay(alignment: .bottomTrailing) {
            NarrowFAB { router.push(.capture) }.padding(20)
        }
        .overlay {
            if let moving {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                    moveDialog(moving)
                        .scaleEffect(min(1, (size.width - 32) / 480))
                        .transition(.opacity.combined(with: .offset(y: 40)).animation(.easeOut(duration: 0.4).delay(0.05)))
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            if startsMoving { withAnimation(.easeOut(duration: 0.3)) { moving = items.first } }
        }
    }
}
