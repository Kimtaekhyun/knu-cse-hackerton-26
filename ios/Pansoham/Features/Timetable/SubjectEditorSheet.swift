//
//  SubjectEditorSheet.swift
//  chalkdrop
//
//  시간표 확인(06)의 과목 추가 · 고치기 창.
//  요일은 눌러서, 시간은 돌려서 골라요. 저장하면 "월 10:30–12:00" 형태 글자로 바꿔요.
//

import SwiftUI

struct SubjectEditorSheet: View {
    /// nil 이면 새 과목 추가
    let subject: TimetableSubject?
    /// 시간이 겹치는지 볼 다른 과목들 (고치는 과목은 빼고)
    var others: [TimetableSubject] = []
    let onSave: (_ name: String, _ time: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var slots: [Slot]

    init(subject: TimetableSubject?, others: [TimetableSubject] = [],
         onSave: @escaping (_ name: String, _ time: String) -> Void) {
        self.subject = subject
        self.others = others
        self.onSave = onSave
        _name = State(initialValue: subject?.name ?? "")
        let parsed = Slot.parse(subject?.time ?? "")
        _slots = State(initialValue: parsed.isEmpty ? [Slot()] : parsed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("과목 이름") {
                    TextField("예: 자료구조", text: $name)
                }

                ForEach($slots) { $slot in
                    Section {
                        // 왼쪽 요일 · 오른쪽 시작–끝 시간, 모두 돌려서 골라요
                        HStack(spacing: 0) {
                            Picker("요일", selection: $slot.weekday) {
                                ForEach(Slot.days.indices, id: \.self) { Text(Slot.days[$0]).tag($0) }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 90)
                            .padding(.trailing, 16)
                            TimeWheel(minutes: $slot.start)
                            Text("–").font(.title3.weight(.semibold)).padding(.horizontal, 8)
                            TimeWheel(minutes: $slot.end)
                        }
                        .frame(height: 150)
                    } header: {
                        HStack {
                            Text(slot.text)
                            Spacer()
                            if slots.count > 1 {
                                Button("삭제", role: .destructive) {
                                    withAnimation { slots.removeAll { $0.id == slot.id } }
                                }
                                .font(.footnote)
                            }
                        }
                    } footer: {
                        if slot.end <= slot.start {
                            Text("끝나는 시간이 시작 시간보다 늦어야 해요.").foregroundStyle(.red)
                        } else if let clash = clash(for: slot) {
                            Text(clash).foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button {
                        // 새 칸은 마지막 칸 시간을 그대로, 요일만 다음 날로
                        var next = slots.last ?? Slot()
                        next = Slot(weekday: min(next.weekday + 1, 6), start: next.start, end: next.end)
                        withAnimation { slots.append(next) }
                    } label: {
                        Label("요일 · 시간 추가", systemImage: "plus")
                    }
                } footer: {
                    Text("미리 보기: \(Slot.text(slots))")
                }
            }
            .navigationTitle(subject == nil ? "과목 추가" : "과목 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(subject == nil ? "추가" : "저장") {
                        onSave(trimmedName, Slot.text(slots))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedName.isEmpty && slots.allSatisfy { $0.end > $0.start && clash(for: $0) == nil }
    }

    /// 이 칸과 시간이 겹치는 수업이 있으면 안내 문구. 다른 과목과 이 과목의 다른 칸을 모두 봐요.
    private func clash(for slot: Slot) -> String? {
        for other in others {
            if let hit = Slot.parse(other.time).first(where: slot.overlaps) {
                return "\(hit.text)에 이미 '\(other.name)' 수업이 있어요."
            }
        }
        if let hit = slots.first(where: { $0.id != slot.id && slot.overlaps($0) }) {
            return "이 과목의 \(hit.text) 칸과 시간이 겹쳐요."
        }
        return nil
    }
}

// MARK: - 수업 칸 하나 (요일 + 시작 · 끝)

struct Slot: Identifiable, Equatable {
    static let days = ["월", "화", "수", "목", "금", "토", "일"]

    let id = UUID()
    var weekday = 0
    /// 자정부터 센 분 (10:30 → 630)
    var start = 9 * 60
    var end = 10 * 60 + 30

    /// 같은 요일에 시간이 조금이라도 겹치는지 (끝나는 시각에 바로 시작하는 건 괜찮아요)
    func overlaps(_ other: Slot) -> Bool {
        weekday == other.weekday && start < other.end && other.start < end
    }

    var text: String { "\(Self.days[weekday]) \(Self.clock(start))–\(Self.clock(end))" }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 서버 결과와 같은 규칙: 시간이 모두 같으면 "화 · 목 10:30–12:00", 다르면 "화 10:30–12:00 · 목 13:00–14:30"
    static func text(_ slots: [Slot]) -> String {
        TimetableAPI.timeText(slots.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }.map {
            TimetableAPI.SlotDTO(weekday: $0.weekday, start: clock($0.start), end: clock($0.end))
        })
    }

    /// "월 · 수 16:30–18:00" · "화 13:30–16:30 · 목 15:00–18:00" 같은 글자를 칸들로. 못 읽으면 빈 목록.
    static func parse(_ text: String) -> [Slot] {
        var result: [Slot] = []
        var pendingDays: [Int] = []  // 시간 없이 앞에 나온 요일 (같은 시간을 나눠 써요)
        for part in text.components(separatedBy: " · ") {
            let words = part.split(separator: " ")
            guard let first = words.first, let day = days.firstIndex(of: String(first)) else { continue }
            guard words.count == 2 else { pendingDays.append(day); continue }
            let times = words[1].split(separator: "–").compactMap { minutes(String($0)) }
            guard times.count == 2 else { continue }
            for d in pendingDays + [day] {
                result.append(Slot(weekday: d, start: times[0], end: times[1]))
            }
            pendingDays = []
        }
        return result
    }

    private static func minutes(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

// MARK: - 시 · 분 돌림판

/// 시(0~23)와 분(5분 단위)을 돌려서 고르는 돌림판
private struct TimeWheel: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 0) {
            Picker("시", selection: hour) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.wheel)
            Text(":").font(.title3.weight(.semibold))
            Picker("분", selection: minute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) {
                    Text(String(format: "%02d", $0)).tag($0)
                }
            }
            .pickerStyle(.wheel)
        }
    }

    private var hour: Binding<Int> {
        Binding { minutes / 60 } set: { minutes = $0 * 60 + minutes % 60 }
    }

    /// 5분 단위가 아닌 값(서버가 읽은 10:32 등)은 가까운 5분으로 맞춰 보여 줘요.
    private var minute: Binding<Int> {
        Binding { (minutes % 60) / 5 * 5 } set: { minutes = minutes / 60 * 60 + $0 }
    }
}
