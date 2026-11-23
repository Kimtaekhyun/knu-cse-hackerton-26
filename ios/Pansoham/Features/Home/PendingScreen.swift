//
//  PendingScreen.swift
//  chalkdrop
//
//  아직 옮기지 않은 판서 전체 목록.
//  피그마에는 없는 화면이라 메인(08)의 "아직 옮기지 않은 판서" 카드 모양을 크게 늘려 만들었어요.
//  메인의 `모두 보기` · 종 아이콘에서 들어와요.
//

import SwiftUI

struct PendingNote: Identifiable {
    var id = UUID()
    let title: String
    let detail: String
    /// 판서 사진에서 보여 줄 부분 (BoardPhoto 의 x · y)
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// 서버 판서 사진 (있으면 샘플 사진 대신)
    var photo: UIImage? = nil
    /// 누르면 열 결과 화면 (서버 판서)
    var job: CaptureFlow.Job? = nil
    /// 결과 화면 위쪽에 보일 곳 (과목 이름 · "미분류함")
    var place: String = ""

    /// 서버 판서를 쓰는지 (로그인했을 때)
    static var isLive: Bool { AuthSession.shared.isLoggedIn }

    /// 아직 옮기지 않은 판서 (서버). 최신부터
    static var live: [PendingNote] {
        let subjects = SemesterStore.shared.subjects
        return SubjectCaptures.unmoved.latest.map { item in
            let place = item.capture.subjectId.flatMap { id in subjects.first { $0.id == id }?.name } ?? "미분류함"
            return PendingNote(id: item.id, title: item.placeAndDate(subjects: subjects), detail: item.unmovedSummary,
                               photo: item.photo, job: item.job, place: place)
        }
    }

    /// 화면에 보여 줄 목록: 로그인했으면 서버, 아니면 샘플
    static var current: [PendingNote] { isLive ? live : SampleData.pending }

    /// 누르면: 서버 판서면 그 판서의 결과 화면, 샘플이면 샘플 결과
    func open(_ router: Router) {
        if let job { CaptureFlow.shared.open([job], folder: place) } else if PendingNote.isLive { return }
        router.push(.result)
    }

    /// 사진 미리보기
    @ViewBuilder
    func thumb(width: CGFloat, height: CGFloat, scale: CGFloat, radius: CGFloat) -> some View {
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            BoardPhoto(width: width, height: height, scaleX: scale, scaleY: scale, x: x, y: y, radius: radius)
        }
    }
}

extension SampleData {
    static let pending: [PendingNote] = [
        .init(title: "자료구조 · 오늘 10:42", detail: "카드 4개 · 필기 앱으로 옮기지 않았어요", x: -0.5, y: -0.1667),
        .init(title: "컴퓨터구조 · 11월 11일", detail: "카드 6개 · 6일째 그대로예요", x: -0.0333, y: -0.6667),
        .init(title: "이산수학 · 11월 13일", detail: "카드 3개 · 4일째 그대로예요", x: -0.3333, y: -0.4),
    ]
}

struct PendingScreen: View {
    @Environment(Router.self) private var router

    private var notes: [PendingNote] { PendingNote.current }
    private let title = "아직 옮기지 않은 판서"
    private var detail: String {
        if PendingNote.isLive, !SubjectCaptures.unmoved.isLoaded(.unmoved) {
            if case .failed(let message) = SubjectCaptures.unmoved.state { return "불러오지 못했어요 · \(message)" }
            return "불러오는 중…"
        }
        return notes.isEmpty ? "모든 판서를 옮겼어요" : "필기 앱으로 옮기지 않은 판서가 \(notes.count)개 있어요"
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .task {
                guard PendingNote.isLive else { return }
                await SubjectCaptures.unmoved.load(.unmoved)
            }
    }

    // MARK: 넓은 화면

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "chalkdrop", title: "", onBack: { router.pop() })

            VStack(alignment: .leading, spacing: 8) {
                Text(title).ds(34, .bold)
                Text(detail).ds(17, .regular, .dsSub)
            }
            .at(48, 96)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(notes) { note in row(note, width: 720) }
                }
                .padding(.bottom, 40)
            }
            .frame(width: 720, height: DS.height - 200, alignment: .top)
            .at(48, 200)
        }
    }

    // MARK: 좁은 화면 (스플릿 뷰)

    private func narrow(_ size: CGSize) -> some View {
        NarrowPage(backTitle: "chalkdrop", onBack: { router.pop() }, title: title, detail: detail,
                   trailing: { EmptyView() }, content: {
            VStack(spacing: 12) {
                ForEach(notes) { note in row(note, width: size.width - 40) }
            }
        }, bottom: { EmptyView() })
    }

    // MARK: 한 줄 (누르면 결과 화면)

    private func row(_ note: PendingNote, width: CGFloat) -> some View {
        Button { note.open(router) } label: {
            HStack(spacing: 16) {
                note.thumb(width: 104, height: 80, scale: 1.6667, radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title).dsLine(17, .bold)
                    Text(note.detail).dsLine(15, .regular, .dsSub)
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
