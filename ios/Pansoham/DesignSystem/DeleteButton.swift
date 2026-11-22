//
//  DeleteButton.swift
//  chalkdrop
//
//  회색 휴지통 + 글자 버튼 (12 사진 아래 "이 판서 삭제" 등, #93)
//

import SwiftUI

struct DeleteButton: View {
    let title: String
    var busy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "trash").font(.system(size: 14, weight: .medium))
                Text(busy ? "삭제하는 중…" : title).ds(15, .medium, .dsSub)
            }
            .foregroundStyle(Color.dsSub)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

extension View {
    /// 삭제 실패 알림
    func deleteFailedAlert(_ message: Binding<String?>) -> some View {
        alert("삭제하지 못했어요", isPresented: Binding(get: { message.wrappedValue != nil },
                                                      set: { if !$0 { message.wrappedValue = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
