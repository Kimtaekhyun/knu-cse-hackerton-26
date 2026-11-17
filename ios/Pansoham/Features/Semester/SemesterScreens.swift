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

    private let semesters: [(name: String, count: Int, subjects: Int)] = [
        ("2026년 2학기", 28, 5), ("2026년 1학기", 64, 6), ("2025년 2학기", 41, 5), ("2025년 1학기", 52, 6),
    ]

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "chalkdrop", title: "", onBack: { router.pop() })
            PageTitle(title: "전체 학기",
                      detail: "학기가 바뀌면 새 시간표를 올려 주세요. 그 학기의 과목 폴더가 만들어져요.")

            // 폴더 격자
            VStack(alignment: .leading, spacing: 19) {
                HStack(spacing: 19) {
                    ForEach(Array(semesters.enumerated()), id: \.offset) { index, semester in
                        SubjectCard(name: semester.name, detail: "과목 \(semester.subjects)개",
                                    count: semester.count, style: index == 0 ? .blue : .gray, width: 260) {
                            if index == 0 { router.popTo(.home) } else { router.push(.pastSemester) }
                        }
                        .overlay(alignment: .topLeading) {
                            if index == 0 {
                                // 현재 학기 (화면 기준 225, 230)
                                Text("현재 학기").ds(12, .bold, .white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.dsBlue)
                                    .clipShape(Capsule())
                                    .at(177, 34)
                            }
                        }
                        .entrance(appeared, delay: 0.1 + 0.07 * Double(index), duration: 0.4, y: 16)
                    }
                }
                SubjectCard(name: "새 학기 추가", detail: "에브리타임 시간표 올리기",
                            count: 0, style: .dashed, width: 260, symbol: "+") {
                    router.push(.timetableUpload)
                }
                .entrance(appeared, delay: 0.38, duration: 0.4, y: 16)
            }
            .at(48, 196)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - 22 지난 학기 · 2026년 1학기

struct PastSemesterScreen: View {
    @Environment(Router.self) private var router
    @State private var appeared = false

    private let subjects: [(name: String, time: String, count: Int)] = [
        ("알고리즘", "월 13:00–14:30", 14), ("데이터베이스", "화 10:30–12:00", 12),
        ("컴퓨터네트워크", "수 15:00–16:30", 11), ("객체지향프로그래밍", "목 09:00–10:30", 10),
        ("선형대수", "금 10:30–12:00", 9), ("논리회로", "금 13:00–14:30", 8),
    ]

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "전체 학기", title: "", onBack: { router.pop() }) {
                Text("시간표 보기").ds(17, .medium, .dsSub)
            }
            PageTitle(title: "2026년 1학기", detail: "지난 학기 · 과목 6개 · 판서 64장")

            VStack(alignment: .leading, spacing: 19) {
                row(0..<4)
                row(4..<6)
            }
            .at(48, 196)

            Text("지난 학기 판서는 계속 볼 수 있고, 새로 찍은 판서는 현재 학기에 저장돼요.")
                .ds(14, .regular, .dsSub)
                .at(48, 571)
        }
        .onAppear { appeared = true }
    }

    private func row(_ range: Range<Int>) -> some View {
        HStack(spacing: 19) {
            ForEach(Array(range), id: \.self) { index in
                let subject = subjects[index]
                SubjectCard(name: subject.name, detail: subject.time, count: subject.count, width: 260) {
                    router.push(.subjectLessons)
                }
                .entrance(appeared, delay: 0.1 + 0.07 * Double(index), duration: 0.4, y: 16)
            }
        }
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
            NarrowGrid(count: semesters.count + 1) { index in
                if index < semesters.count {
                    let semester = semesters[index]
                    SubjectCard(name: semester.name, detail: "과목 \(semester.subjects)개",
                                count: semester.count, style: index == 0 ? .blue : .gray, width: 260) {
                        if index == 0 { router.popTo(.home) } else { router.push(.pastSemester) }
                    }
                    .overlay(alignment: .topLeading) {
                        if index == 0 {
                            Text("현재 학기").ds(12, .bold, .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.dsBlue)
                                .clipShape(Capsule())
                                .at(177, 34)
                        }
                    }
                    .scaledBox(260, 166, to: cardWidth)
                    .entrance(appeared, delay: 0.1 + 0.07 * Double(index), duration: 0.4, y: 16)
                } else {
                    SubjectCard(name: "새 학기 추가", detail: "에브리타임 시간표 올리기",
                                count: 0, style: .dashed, width: 260, symbol: "+") {
                        router.push(.timetableUpload)
                    }
                    .scaledBox(260, 166, to: cardWidth)
                    .entrance(appeared, delay: 0.38, duration: 0.4, y: 16)
                }
            }
        }, bottom: { EmptyView() })
        .onAppear { appeared = true }
    }
}

extension PastSemesterScreen {
    func narrow(_ size: CGSize) -> some View {
        let cardWidth = (size.width - 40 - 12) / 2
        return NarrowPage(backTitle: "전체 학기", onBack: { router.pop() },
                          title: "2026년 1학기", detail: "지난 학기 · 과목 6개 · 판서 64장",
                          trailing: { Text("시간표 보기").ds(15, .medium, .dsSub) }, content: {
            NarrowGrid(count: subjects.count) { index in
                let subject = subjects[index]
                SubjectCard(name: subject.name, detail: subject.time, count: subject.count, width: 260) {
                    router.push(.subjectLessons)
                }
                .scaledBox(260, 166, to: cardWidth)
                .entrance(appeared, delay: 0.1 + 0.07 * Double(index), duration: 0.4, y: 16)
            }
            Text("지난 학기 판서는 계속 볼 수 있고, 새로 찍은 판서는 현재 학기에 저장돼요.").dsWrap(13, .regular, .dsSub)
        }, bottom: { EmptyView() })
        .onAppear { appeared = true }
    }
}
