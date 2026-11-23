//
//  SchoolPicker.swift
//  chalkdrop
//
//  23-4 학교 입력 창 · 23-6 검색 결과 없음 (#105)
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
    /// 저장된 학교가 있는데 검색 칸을 비우고 아무것도 안 골랐으면 저장 = 학교 비우기 (#122)
    private var clearing: Bool {
        current != nil && selected == nil && query.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canSave: Bool { !saving && (clearing || selected.map { results.contains($0) } == true) }

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

                if results.isEmpty {
                    // 23-6 검색 결과 없음
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(Color.black.opacity(0.2))
                        Text("‘\(query.trimmingCharacters(in: .whitespaces))’ 학교를 찾지 못했어요").ds(17, .bold)
                        Text("학교 이름을 다시 확인해 주세요").ds(13, .regular, .dsSub)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(results, id: \.self) { school in
                            // 고른 학교를 다시 누르면 선택을 풀어요
                            Button { selected = selected == school ? nil : school } label: {
                                HStack {
                                    Text(school).ds(17, .bold)
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
                    if clearing {
                        Text("저장하면 학교를 비워요").ds(13, .regular, .dsSub)
                    }
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
            selected = current.flatMap { School.supported.contains($0) ? $0 : nil }
            if let current { query = current }
            focused = true
        }
        // 검색 칸을 비우면 고른 학교도 풀어요 (#122)
        .onChange(of: query) { _, new in
            if new.trimmingCharacters(in: .whitespaces).isEmpty { selected = nil }
        }
    }
}
