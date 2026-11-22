//
//  SemesterScreens.swift
//  chalkdrop
//
//  21 전체 학기 · 22 지난 학기 (2026년 1학기)
//

import SwiftUI

/// 큰 제목 + 설명 (왼쪽 위)
private struct PageTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).ds(34, .bold)
            Text(detail).ds(17, .regular, .dsSub)
        }
        .at(48, 92)
    }
}

// MARK: - 21 전체 학기

struct AllSemestersScreen: View {
    @Environment(Router.self) private var router
    @State private var appeared = false

    /// 서버의 학기 목록. nil 이면(로그인 안 함 · 불러오기 전) 샘플
    @State private var live: [SemesterAPI.SemesterDTO]?

    struct Item {
        let id: UUID?
        let name: String
        let count: Int
        let subjects: Int
        let isCurrent: Bool
    }

    private var semesters: [Item] {
        if let live {
            return live.map { Item(id: $0.id, name: $0.label, count: $0.captureCount,
                                   subjects: $0.subjectCount, isCurrent: $0.isCurrent) }
        }
        return [("2026년 2학기", 28, 5), ("2026년 1학기", 64, 6), ("2025년 2학기", 41, 5), ("2025년 1학기", 52, 6)]
            .enumerated().map { Item(id: nil, name: $1.0, count: $1.1, subjects: $1.2, isCurrent: $0 == 0) }
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .task {
                guard AuthSession.shared.isLoggedIn else { return }
                live = try? await SemesterAPI.list()
            }
    }

    /// 현재 학기는 메인으로, 지난 학기는 22 로
    func open(_ semester: Item) {
        if semester.isCurrent { router.popTo(.home); return }
        router.pastSemesterID = semester.id
        router.push(.pastSemester)
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "chalkdrop", title: "", onBack: { router.pop() })
            PageTitle(title: "전체 학기",
                      detail: "학기가 바뀌면 새 시간표를 올려 주세요. 그 학기의 과목 폴더가 만들어져요.")

            // 폴더 격자 (4칸씩, 넘치면 스크롤)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 19), count: 4),
                          alignment: .leading, spacing: 19) {
                    ForEach(Array(semesters.enumerated()), id: \.offset) { index, semester in
                        semesterCard(semester)
                            .entrance(appeared, delay: 0.1 + 0.07 * Double(min(index, 6)), duration: 0.4, y: 16)
                    }
                    addCard.entrance(appeared, delay: 0.38, duration: 0.4, y: 16)
                }
            }
            .frame(width: 1098, height: 834 - 196 - 24, alignment: .topLeading)
            .at(48, 196)
        }
        .onAppear { appeared = true }
    }

    func semesterCard(_ semester: Item) -> some View {
        SubjectCard(name: semester.name, detail: "과목 \(semester.subjects)개",
                    count: semester.count, style: semester.isCurrent ? .blue : .gray, width: 260) {
            open(semester)
        }
        .overlay(alignment: .topLeading) {
            if semester.isCurrent {
                Text("현재 학기").ds(12, .bold, .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.dsBlue)
                    .clipShape(Capsule())
                    .at(177, 34)
            }
        }
    }

    var addCard: some View {
        SubjectCard(name: "새 학기 추가", detail: "에브리타임 시간표 올리기",
                    count: 0, style: .dashed, width: 260, symbol: "+") {
            router.startNewSemester()
        }
    }
}

// MARK: - 22 지난 학기 · 2026년 1학기

struct PastSemesterScreen: View {
    @Environment(Router.self) private var router
    @State private var appeared = false

    /// 서버에서 받은 학기. nil 이면 샘플
    @State private var live: SemesterAPI.SemesterDTO?
    @State private var switching = false

    private var subjects: [(name: String, time: String, count: Int, dto: SemesterAPI.SubjectDTO?)] {
        if let live {
            return (live.subjects ?? []).map { ($0.name, $0.timeText, $0.captureCount, $0) }
        }
        return [("알고리즘", "월 13:00–14:30", 14), ("데이터베이스", "화 10:30–12:00", 12),
                ("컴퓨터네트워크", "수 15:00–16:30", 11), ("객체지향프로그래밍", "목 09:00–10:30", 10),
                ("선형대수", "금 10:30–12:00", 9), ("논리회로", "금 13:00–14:30", 8)].map { ($0.0, $0.1, $0.2, nil) }
    }

    var title: String { live?.label ?? "2026년 1학기" }
    var detail: String {
        guard let live else { return "지난 학기 · 과목 6개 · 판서 64장" }
        return "지난 학기 · 과목 \(live.subjectCount)개 · 판서 \(live.captureCount)장"
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .task {
                guard AuthSession.shared.isLoggedIn, let id = router.pastSemesterID else { return }
                live = try? await SemesterAPI.detail(id)
            }
    }

    /// 과목 폴더 열기
    func open(_ index: Int) {
        // 누르는 사이 목록이 바뀌었을 수 있어 범위를 확인해요 (#87)
        let list = subjects
        guard list.indices.contains(index) else { return }
        let subject = list[index]
        router.subject = subject.dto
        router.push(subject.dto?.captureCount == 0 ? .subjectEmpty : .subjectLessons)
    }

    /// 오른쪽 위: 서버 학기면 `현재 학기로`, 샘플이면 `시간표 보기`
    @ViewBuilder
    func trailingAction(_ size: CGFloat) -> some View {
        if let live {
            Button {
                switching = true
                Task {
                    defer { switching = false }
                    guard (try? await SemesterAPI.makeCurrent(live.id)) != nil else { return }
                    await SemesterStore.shared.reload()
                    router.popTo(.home)
                }
            } label: {
                Text(switching ? "바꾸는 중…" : "현재 학기로").ds(size, .bold, .dsBlue)
            }
            .buttonStyle(.plain)
            .disabled(switching)
        } else {
            Text("시간표 보기").ds(size, .medium, .dsSub)
        }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "전체 학기", title: "", onBack: { router.pop() }) {
                trailingAction(17)
            }
            PageTitle(title: title, detail: detail)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 19), count: 4),
                          alignment: .leading, spacing: 19) {
                    ForEach(subjects.indices, id: \.self) { index in
                        let subject = subjects[index]
                        SubjectCard(name: subject.name, detail: subject.time, count: subject.count, width: 260) {
                            open(index)
                        }
                        .entrance(appeared, delay: 0.1 + 0.07 * Double(min(index, 6)), duration: 0.4, y: 16)
                    }
                }
            }
            .frame(width: 1098, height: 352, alignment: .topLeading)
            .at(48, 196)

            Text("지난 학기 판서는 계속 볼 수 있고, 새로 찍은 판서는 현재 학기에 저장돼요.")
                .ds(14, .regular, .dsSub)
                .at(48, 571)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension AllSemestersScreen {
    func narrow(_ size: CGSize) -> some View {
        let cardWidth = (size.width - 40 - 12) / 2
        return NarrowPage(backTitle: "chalkdrop", onBack: { router.pop() },
                          title: "전체 학기",
                          detail: "학기가 바뀌면 새 시간표를 올려 주세요. 그 학기의 과목 폴더가 만들어져요.",
                          trailing: { EmptyView() }, content: {
            // 목록은 한 번만 꺼내 개수와 내용을 같은 값으로 써요 (#87)
            let items = semesters
            NarrowGrid(count: items.count + 1) { index in
                Group {
                    if index < items.count { semesterCard(items[index]) } else { addCard }
                }
                .scaledBox(260, 166, to: cardWidth)
                .entrance(appeared, delay: 0.1 + 0.07 * Double(min(index, 6)), duration: 0.4, y: 16)
            }
        }, bottom: { EmptyView() })
        .onAppear { appeared = true }
    }
}

extension PastSemesterScreen {
    func narrow(_ size: CGSize) -> some View {
        let cardWidth = (size.width - 40 - 12) / 2
        return NarrowPage(backTitle: "전체 학기", onBack: { router.pop() },
                          title: title, detail: detail,
                          trailing: { trailingAction(15) }, content: {
            // 목록은 한 번만 꺼내 개수와 내용을 같은 값으로 써요 (#87)
            let items = subjects
            NarrowGrid(count: items.count) { index in
                let subject = items[index]
                SubjectCard(name: subject.name, detail: subject.time, count: subject.count, width: 260) {
                    open(index)
                }
                .scaledBox(260, 166, to: cardWidth)
                .entrance(appeared, delay: 0.1 + 0.07 * Double(index), duration: 0.4, y: 16)
            }
            Text("지난 학기 판서는 계속 볼 수 있고, 새로 찍은 판서는 현재 학기에 저장돼요.").dsWrap(13, .regular, .dsSub)
        }, bottom: { EmptyView() })
        .onAppear { appeared = true }
    }
}
