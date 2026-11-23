//
//  SemesterPickerSheet.swift
//  chalkdrop
//
//  시간표 확인(06)의 학기 고르기 창. 왼쪽 연도 · 오른쪽 학기를 돌려서 골라요.
//

import SwiftUI

struct SemesterPickerSheet: View {
    let onSave: (Semester) -> Void
    /// 이미 있는 학기 (새 학기 추가에서는 고를 수 없어요, #146)
    let taken: Set<Semester>

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var term: Semester.Term

    /// 고를 수 있는 연도: 올해 기준 10년 전 ~ 5년 뒤 (고르던 연도가 밖이면 그 연도도 넣어요)
    private let years: [Int]

    init(semester: Semester, taken: Set<Semester>, onSave: @escaping (Semester) -> Void) {
        self.onSave = onSave
        self.taken = taken
        _year = State(initialValue: semester.year)
        _term = State(initialValue: semester.term)
        let now = Calendar.current.component(.year, from: .now)
        years = Array(Set(Array((now - 10)...(now + 5)) + [semester.year])).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                // 왼쪽 연도 · 오른쪽 학기, 둘 다 돌려서 골라요
                HStack(spacing: 0) {
                    Picker("연도", selection: $year) {
                        ForEach(years, id: \.self) { Text(verbatim: "\($0)년").tag($0) }
                    }
                    .pickerStyle(.wheel)

                    Picker("학기", selection: $term) {
                        ForEach(Semester.Term.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 180)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if isTaken {
                    Text("이미 있는 학기예요. 전체 학기에서 열어 고쳐 주세요.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.leading, 16)
                } else {
                    Text("미리 보기: \(Semester(year: year, term: term).title)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("학기 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        onSave(Semester(year: year, term: term))
                        dismiss()
                    }
                    .disabled(isTaken)
                }
            }
        }
        // 휠 두 개만 들어가는 창이라 내용 높이에 맞춰 작게 띄워요
        // (아이패드 가운데 창은 fitted 크기, 좁은 창 · 아이폰은 아래에서 올라오는 높이)
        .frame(idealWidth: 480, idealHeight: Self.height)
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        .presentationDetents([.height(Self.height)])
    }

    private var isTaken: Bool { taken.contains(Semester(year: year, term: term)) }

    /// 위 막대 + 휠(180) + 미리 보기 + 여백
    private static let height: CGFloat = 320
}

/// 지금 고른 학기를 보여 주는 버튼 (예: "2026년 2학기 ⌄"). 누르면 학기 고르기 창.
struct SemesterChip: View {
    let title: String
    var compact = false
    /// 시간표 수정에서는 학기를 바꿀 수 없어요 (화살표 없이 글자만, #146)
    var locked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).ds(compact ? 15 : 17, .bold)
                if !locked {
                    Image(systemName: "chevron.down").font(.system(size: compact ? 11 : 13, weight: .bold))
                }
            }
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 7 : 10)
            .background(Color.dsPanel, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }
}
