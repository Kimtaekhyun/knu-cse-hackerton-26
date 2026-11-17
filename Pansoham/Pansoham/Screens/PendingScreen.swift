//
//  PendingScreen.swift
//  판서함
//
//  아직 옮기지 않은 판서 전체 목록.
//  피그마에는 없는 화면이라 메인(08)의 "아직 옮기지 않은 판서" 카드 모양을 크게 늘려 만들었어요.
//  메인의 `모두 보기` · 종 아이콘에서 들어와요.
//

import SwiftUI

struct PendingNote: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    /// 판서 사진에서 보여 줄 부분 (BoardPhoto 의 x · y)
    let x: CGFloat
    let y: CGFloat
}

extension SampleData {
    static let pending: [PendingNote] = [
        .init(title: "자료구조 · 오늘 10:42", detail: "카드 4개 · 굿노트로 옮기지 않았어요", x: -0.5, y: -0.1667),
        .init(title: "컴퓨터구조 · 11월 11일", detail: "카드 6개 · 6일째 그대로예요", x: -0.0333, y: -0.6667),
        .init(title: "이산수학 · 11월 13일", detail: "카드 3개 · 4일째 그대로예요", x: -0.3333, y: -0.4),
    ]
}

struct PendingScreen: View {
    @Environment(Router.self) private var router

    private let notes = SampleData.pending
    private let title = "아직 옮기지 않은 판서"
    private var detail: String { "굿노트로 옮기지 않은 판서가 \(notes.count)개 있어요" }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    // MARK: 넓은 화면

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "판서함", title: "", onBack: { router.pop() })

            VStack(alignment: .leading, spacing: 8) {
                Text(title).ds(34, .bold)
                Text(detail).ds(17, .regular, .dsSub)
            }
            .at(48, 96)

            VStack(spacing: 12) {
                ForEach(notes) { note in row(note, width: 720) }
            }
            .at(48, 200)
        }
    }

    // MARK: 좁은 화면 (스플릿 뷰)

    private func narrow(_ size: CGSize) -> some View {
        NarrowPage(backTitle: "판서함", onBack: { router.pop() }, title: title, detail: detail,
                   trailing: { EmptyView() }, content: {
            VStack(spacing: 12) {
                ForEach(notes) { note in row(note, width: size.width - 40) }
            }
        }, bottom: { EmptyView() })
    }

    // MARK: 한 줄 (누르면 결과 화면)

    private func row(_ note: PendingNote, width: CGFloat) -> some View {
        Button { router.push(.result) } label: {
            HStack(spacing: 16) {
                BoardPhoto(width: 104, height: 80, scaleX: 1.6667, scaleY: 1.6667, x: note.x, y: note.y, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title).ds(17, .bold)
                    Text(note.detail).ds(15, .regular, .dsSub)
                }
                Spacer(minLength: 0)
                Image("chevron-right-20")
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            .frame(width: width)
            .background(Color.dsBlueSoft)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
