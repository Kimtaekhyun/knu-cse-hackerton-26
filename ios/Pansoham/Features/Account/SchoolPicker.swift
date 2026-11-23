//
//  SchoolPicker.swift
//  chalkdrop
//
//  23-4 학교 입력 창 (#105)
//  목록에 없는 학교도 이름을 그대로 저장할 수 있어요. 학사일정은 서버가 웹 검색으로 찾아요 (#173).
//

import SwiftUI

struct SchoolPicker: View {
    /// 지금 저장된 학교 (없으면 nil)
    let current: String?
    var saving = false
    var onCancel: () -> Void
    var onSave: (String) -> Void

    @State private var query = ""
    @State private var selected: String?
    @FocusState private var focused: Bool

    private var results: [String] { School.search(query) }
    private var typed: String { query.trimmingCharacters(in: .whitespaces) }
    /// 목록에 똑같은 이름이 없으면 입력한 이름 그대로 고를 수 있게 보여 줘요
    private var custom: String? {
        typed.isEmpty || typed.count > School.maxLength || results.contains(typed) ? nil : typed
    }
    /// 저장된 학교가 있는데 검색 칸을 비우고 아무것도 안 골랐으면 저장 = 학교 비우기 (#122)
    private var clearing: Bool {
        current != nil && selected == nil && query.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canSave: Bool { !saving && (clearing || selected != nil) }

    var body: some View {
        VStack(spacing: 0) {
            // 위 막대
            HStack {
                Button(action: onCancel) { Text("취소").ds(17, .medium, .dsSub) }
                    .buttonStyle(.plain)
                Spacer()
                Text("학교").ds(17, .bold)
                Spacer()
                Button { if let selected { onSave(selected) } else if clearing { onSave("") } } label: {
                    Text(saving ? "저장 중…" : "저장").ds(17, .bold, canSave ? .dsBlue : .dsSub)
                        .opacity(canSave ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                // 검색 칸
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.dsSub)
                    TextField("학교 이름", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .medium))
                        .focused($focused)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.black.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.dsPanel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // 짧으면 그대로, 길면(빈 칸일 때 전체 목록) 스크롤
                ViewThatFits(in: .vertical) {
                    schoolList
                    ScrollView { schoolList }
                }
                .frame(maxHeight: 320)
                VStack(alignment: .leading, spacing: 4) {
                    if clearing {
                        Text("저장하면 학교를 비워요").ds(13, .regular, .dsSub)
                    }
                    Text("시험 일정은 학교 학사일정을 찾아 자동으로 맞춰요").ds(13, .regular, .dsSub)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .frame(width: 540)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            selected = current
            if let current { query = current }
            focused = true
        }
        // 검색 칸을 비우면 고른 학교도 풀어요 (#122)
        .onChange(of: query) { _, new in
            let typed = new.trimmingCharacters(in: .whitespaces)
            if typed.isEmpty { selected = nil }
            // 직접 입력한 이름을 골랐다가 글자를 바꾸면 선택을 풀어요
            if let selected, !School.known.contains(selected), selected != typed { self.selected = nil }
        }
    }

    private var schoolList: some View {
        VStack(spacing: 0) {
            if let custom {
                row(custom, hint: "목록에 없는 학교 · 이 이름 그대로 저장")
            }
            ForEach(results, id: \.self) { school in row(school) }
        }
    }

    /// 학교 한 줄. 고른 학교를 다시 누르면 선택을 풀어요
    private func row(_ school: String, hint: String? = nil) -> some View {
        Button { selected = selected == school ? nil : school } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(school).ds(17, .bold)
                    if let hint { Text(hint).ds(13, .regular, .dsSub) }
                }
                Spacer()
                if selected == school {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.dsBlue)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
