//
//  HomeScreen.swift
//  판서함
//
//  07 메인 · 처음 (판서 0장) / 08 메인 (판서가 쌓인 뒤)
//

import SwiftUI

struct HomeScreen: View {
    /// true 면 07 "처음" 화면, false 면 08 화면
    var isFirst = false

    @Environment(Router.self) private var router
    @State private var appeared = false

    /// 08 에서만 카드 · 알림 · 막대가 차례로 나타나요. 07 은 처음부터 다 보여요.
    private var shown: Bool { isFirst || appeared }

    private var counts: [Int] { isFirst ? [0, 0, 0, 0, 0, 0] : [12, 8, 5, 3, 0, 3] }

    var body: some View {
        // 피그마 타임라인: 07 은 3.2초, 08 은 2.8초 되풀이 (안내 말풍선 · 수업 중 점)
        Motion(loop: isFirst ? 3.2 : 2.8) { t in
            Adaptive { canvas(t) } narrow: { narrow($0, t) }
        }
            .onAppear { appeared = true }
    }

    private func canvas(_ t: Double) -> some View {
        DesignCanvas {
            topBar
            leftColumn(t).at(24, 112)
            rightColumn.at(408, 112)

            // 촬영 버튼
            Button { router.push(.capture) } label: {
                Image("camera-30")
                    .frame(width: 72, height: 72)
                    .background(Color.black)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .at(1082, 722)

            if isFirst {
                // 첫 촬영 안내
                Group {
                    Button { router.push(.capture) } label: {
                        Text("여기를 눌러 첫 판서를 찍어 보세요").ds(15, .bold, .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .at(910, 664)
                    Image("tooltip-tail").at(1109, 706)
                }
                .offset(y: t < 0.7 ? tween(t, 0, -8, 0, 0.7, .inOut)
                           : t < 1.4 ? tween(t, -8, 0, 0.7, 1.4, .inOut)
                           : t < 2.1 ? tween(t, 0, -8, 1.4, 2.1, .inOut)
                           : tween(t, -8, 0, 2.1, 2.8, .inOut))
            } else {
                Image("bell-dot").at(1092, 49).allowsHitTesting(false)
            }
        }
    }

    // MARK: 위 막대

    private var topBar: some View {
        HStack {
            Text("판서함").ds(34, .bold)
            Spacer()
            HStack(spacing: 20) {
                Button { router.push(.pending) } label: { Image("bell") }
                    .buttonStyle(.plain)
                Button { router.push(.account) } label: {
                    Text("김").ds(15, .bold, .white)
                        .frame(width: 34, height: 34)
                        .background(Color.black)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
        .frame(width: DS.width, height: 76)
        .at(0, 24)
    }

    // MARK: 왼쪽 (오늘)

    private func leftColumn(_ t: Double) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            nowCard(t)
            todayList()
            if !isFirst { pendingPanel() }
        }
    }

    private func nowCard(_ t: Double, width: CGFloat = 340) -> some View {
        // 수업 중 점: 0.6초마다 1 ↔ 0.25 (08 에만 있어요)
        let dot = isFirst ? 1
            : t < 0.6 ? tween(t, 1, 0.25, 0, 0.6, .inOut)
            : t < 1.2 ? tween(t, 0.25, 1, 0.6, 1.2, .inOut)
            : t < 1.8 ? tween(t, 1, 0.25, 1.2, 1.8, .inOut)
            : tween(t, 0.25, 1, 1.8, 2.4, .inOut)
        return nowCardBody(dot, width: width)
    }

    private func nowCardBody(_ dot: Double, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("dot-blue-8").opacity(dot)
                Text("수업 중").ds(14, .bold, .white)
            }
            Color.clear.frame(width: 1, height: 14)
            Text("자료구조").ds(34, .bold, .white)
            Color.clear.frame(width: 1, height: 4)
            Text("IT-5호관 245 · 12:00에 끝나요").ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 20)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: width - 48, height: 6)
                Capsule().fill(Color.dsBlue).frame(width: (width - 48) * 0.6, height: 6)
            }
            Color.clear.frame(width: 1, height: 10)
            HStack {
                Text("10:30").ds(12, .medium, .dsSub)
                Spacer()
                Text("42분 남음").ds(12, .medium, .white)
            }
            .frame(width: width - 48)
            Color.clear.frame(width: 1, height: 20)
        }
        .padding(.top, 22)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
        .frame(width: width, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func todayList(_ width: CGFloat = 340) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("오늘 수업").ds(20, .bold)
            Color.clear.frame(width: 1, height: 6)
            todayRow(time: "10:30", name: "자료구조", bold: true, width: width) {
                Text("지금").ds(12, .bold, .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.dsBlue)
                    .clipShape(Capsule())
            }
            todayRow(time: "13:00", name: "컴퓨터구조", width: width) { Text("2시간 뒤").ds(13, .regular, .dsSub) }
            todayRow(time: "15:00", name: "이산수학", width: width) { Text("4시간 뒤").ds(13, .regular, .dsSub) }
        }
    }

    private func todayRow<Trailing: View>(time: String, name: String, bold: Bool = false, width: CGFloat = 340,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            HStack(spacing: 16) {
                Text(time).ds(15, .medium, .dsSub)
                Text(name).ds(17, bold ? .bold : .medium)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 10)
        .frame(width: width)
    }

    /// 아직 옮기지 않은 판서 (08 에만 있어요)
    private func pendingPanel(_ width: CGFloat = 340) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Text("아직 옮기지 않은 판서").ds(16, .bold)
                    Text("3").ds(12, .bold, .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.dsBlue)
                        .clipShape(Capsule())
                }
                Spacer()
                Button { router.push(.pending) } label: {
                    Text("모두 보기").ds(13, .medium, .dsSub)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            pendingRow(title: "자료구조 · 오늘 10:42", detail: "카드 4개 · 굿노트로 옮기지 않았어요", x: -0.5, y: -0.1667)
                .entrance(shown, delay: 0.5, duration: 0.35, y: 12)
            pendingRow(title: "컴퓨터구조 · 11월 11일", detail: "카드 6개 · 6일째 그대로예요", x: -0.0333, y: -0.6667)
                .entrance(shown, delay: 0.62, duration: 0.35, y: 12)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 16)
        .frame(width: width)
        .background(Color.dsBlueSoft)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func pendingRow(title: String, detail: String, x: CGFloat, y: CGFloat) -> some View {
        Button { router.push(.result) } label: {
            HStack(spacing: 12) {
                BoardPhoto(width: 52, height: 40, scaleX: 1.6667, scaleY: 1.6667, x: x, y: y)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).ds(14, .bold)
                    Text(detail).ds(12, .regular, .dsSub)
                }
                Spacer(minLength: 0)
                Image("chevron-right-18")
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 오른쪽 (과목 폴더)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("2026년 2학기").ds(20, .bold)
                Spacer()
                Button { router.push(.allSemesters) } label: {
                    HStack(spacing: 2) {
                        Text("전체 학기").ds(15, .bold)
                        Image("chevron-18").rotationEffect(.degrees(180))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 746)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 19) {
                    SubjectCard(name: "자료구조", detail: "월 10:30–12:00", count: counts[0], style: .blue) {
                        router.push(isFirst ? .subjectEmpty : .subjectLessons)
                    }
                    .entrance(shown, delay: 0.10, duration: 0.45, y: 18)
                    SubjectCard(name: "컴퓨터구조", detail: "화 13:00–14:30", count: counts[1]) {
                        router.push(isFirst ? .subjectEmpty : .subjectLessons)
                    }
                    .entrance(shown, delay: 0.17, duration: 0.45, y: 18)
                    SubjectCard(name: "확률과 통계", detail: "수 09:00–10:30", count: counts[2]) {
                        router.push(isFirst ? .subjectEmpty : .subjectLessons)
                    }
                    .entrance(shown, delay: 0.24, duration: 0.45, y: 18)
                }
                HStack(spacing: 19) {
                    SubjectCard(name: "이산수학", detail: "목 15:00–16:30", count: counts[3]) {
                        router.push(isFirst ? .subjectEmpty : .subjectLessons)
                    }
                    .entrance(shown, delay: 0.31, duration: 0.45, y: 18)
                    SubjectCard(name: "운영체제", detail: "금 10:30–12:00", count: counts[4]) {
                        router.push(.subjectEmpty)
                    }
                    .entrance(shown, delay: 0.38, duration: 0.45, y: 18)
                    SubjectCard(name: "미분류함", detail: "시간표 밖에서 찍은 판서", count: counts[5], style: .dashed) {
                        router.push(.unsorted)
                    }
                    .entrance(shown, delay: 0.45, duration: 0.45, y: 18)
                }
            }

            weekChart
        }
    }

    // MARK: 이번 주

    private var weekChart: some View {
        let bars: [(day: String, height: CGFloat, today: Bool)] = isFirst
            ? ["월", "화", "수", "목", "금", "토", "일"].map { ($0, 6, false) }
            : [("월", 54, false), ("화", 36, false), ("수", 24, false), ("목", 72, true),
               ("금", 6, false), ("토", 6, false), ("일", 6, false)]

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    Text("이번 주").ds(20, .bold)
                    Text(isFirst ? "아직 정리한 판서가 없어요" : "판서 31장 정리").ds(15, .medium, .dsSub)
                }
                Spacer()
                if !isFirst { Text("지난주보다 8장 더").ds(15, .bold) }
            }
            .frame(width: 746)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: bar.height <= 6 ? 3 : 8, style: .continuous)
                            .fill(bar.today ? Color.dsBlue
                                  : bar.height <= 6 ? Color.black.opacity(0.05) : Color.black.opacity(0.14))
                            .frame(width: 82, height: shown ? bar.height : 6)
                            .animation(.easeOut(duration: 0.6).delay(0.5 + 0.06 * Double(index)), value: shown)
                        Text(bar.day).ds(13, bar.today ? .bold : .regular, bar.today ? .black : .dsSub)
                    }
                }
            }
            .frame(height: 106, alignment: .bottom)
        }
        .padding(.top, 40)
        .frame(width: 744, height: 301, alignment: .topLeading)
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension HomeScreen {
    func narrow(_ size: CGSize, _ t: Double) -> some View {
        let inner = size.width - 40
        // 반쪽 폭이면 폴더 3칸, 더 좁으면 2칸
        let folderColumns = inner >= 500 ? 3 : 2
        let cardWidth = (inner - 12 * CGFloat(folderColumns - 1)) / CGFloat(folderColumns)
        let folders: [(name: String, detail: String, style: SubjectCard.Style, to: Screen)] = [
            ("자료구조", "월 10:30–12:00", .blue, isFirst ? .subjectEmpty : .subjectLessons),
            ("컴퓨터구조", "화 13:00–14:30", .gray, isFirst ? .subjectEmpty : .subjectLessons),
            ("확률과 통계", "수 09:00–10:30", .gray, isFirst ? .subjectEmpty : .subjectLessons),
            ("이산수학", "목 15:00–16:30", .gray, isFirst ? .subjectEmpty : .subjectLessons),
            ("운영체제", "금 10:30–12:00", .gray, .subjectEmpty),
            ("미분류함", "시간표 밖에서 찍은 판서", .dashed, .unsorted),
        ]
        // 안내 말풍선 움직임 (07)
        let bob = t < 0.7 ? tween(t, 0, -8, 0, 0.7, .inOut)
            : t < 1.4 ? tween(t, -8, 0, 0.7, 1.4, .inOut)
            : t < 2.1 ? tween(t, 0, -8, 1.4, 2.1, .inOut)
            : tween(t, -8, 0, 2.1, 2.8, .inOut)

        return VStack(spacing: 0) {
            // 위 막대
            HStack {
                Text("판서함").ds(28, .bold)
                Spacer()
                HStack(spacing: 20) {
                    Button { router.push(.pending) } label: {
                        Image("bell").overlay(alignment: .topLeading) {
                            if !isFirst { Image("bell-dot").offset(x: 16, y: -1) }
                        }
                    }
                    .buttonStyle(.plain)
                    Button { router.push(.account) } label: {
                        Text("김").ds(15, .bold, .white)
                            .frame(width: 34, height: 34)
                            .background(Color.black)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .avoidsWindowControls()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    nowCard(t, width: inner)
                    todayList(inner)
                    if !isFirst { pendingPanel(inner) }

                    // 과목 폴더
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("2026년 2학기").ds(20, .bold)
                            Spacer()
                            Button { router.push(.allSemesters) } label: {
                                HStack(spacing: 2) {
                                    Text("전체 학기").ds(15, .bold)
                                    Image("chevron-18").rotationEffect(.degrees(180))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        NarrowGrid(count: folders.count, columns: folderColumns) { index in
                            let folder = folders[index]
                            SubjectCard(name: folder.name, detail: folder.detail, count: counts[index], style: folder.style) {
                                router.push(folder.to)
                            }
                            .scaledBox(236, 166, to: cardWidth)
                            .entrance(shown, delay: 0.1 + 0.07 * Double(index), duration: 0.45, y: 18)
                        }
                    }

                    narrowWeek(inner)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 110)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 0) {
                if isFirst {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("여기를 눌러 첫 판서를 찍어 보세요").ds(15, .bold, .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Image("tooltip-tail").padding(.trailing, 23)
                    }
                    .offset(y: bob)
                    .padding(.bottom, 8)
                }
                NarrowFAB { router.push(.capture) }
            }
            .padding(20)
        }
    }

    /// 이번 주 막대 그래프 (너비에 맞춰 막대 굵기를 정해요)
    private func narrowWeek(_ width: CGFloat) -> some View {
        let days = ["월", "화", "수", "목", "금", "토", "일"]
        let heights: [CGFloat] = isFirst ? [6, 6, 6, 6, 6, 6, 6] : [54, 36, 24, 72, 6, 6, 6]
        let bar = (width - 8 * 6) / 7
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("이번 주").ds(20, .bold)
                Text(isFirst ? "아직 정리한 판서가 없어요" : "판서 31장 정리").ds(14, .medium, .dsSub)
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    let height = heights[index]
                    let today = !isFirst && index == 3
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: height <= 6 ? 3 : 8, style: .continuous)
                            .fill(today ? Color.dsBlue : height <= 6 ? Color.black.opacity(0.05) : Color.black.opacity(0.14))
                            .frame(width: bar, height: shown ? height : 6)
                            .animation(.easeOut(duration: 0.6).delay(0.5 + 0.06 * Double(index)), value: shown)
                        Text(days[index]).ds(13, today ? .bold : .regular, today ? .black : .dsSub)
                    }
                }
            }
            .frame(height: 100, alignment: .bottom)
            if !isFirst { Text("지난주보다 8장 더").ds(15, .bold) }
        }
    }
}
