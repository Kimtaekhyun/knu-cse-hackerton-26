//
//  CaptureMenu.swift
//  chalkdrop
//
//  메인 촬영 버튼 펼침 (피그마 08-1) · 앨범에서 여러 장 고른 뒤 확인 (08-2)
//  촬영 버튼을 누르면 위로 `앨범에서 선택` · `사진 촬영` 이 펼쳐져요.
//  수업이 끝나고 여러 장을 올릴 때 카메라를 거치지 않고 바로 앨범을 열 수 있어요.
//

import SwiftUI

/// 한 번에 고를 수 있는 판서 사진 수
let maxAlbumPhotos = 10

/// 촬영 버튼 + 위로 펼쳐지는 두 갈래 버튼
struct CaptureMenu: View {
    @Binding var isOpen: Bool
    /// 촬영 버튼 지름 (넓은 화면 72, 좁은 화면 64)
    var size: CGFloat = 72
    var onCamera: () -> Void
    var onAlbum: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if isOpen {
                action("앨범에서 선택", systemImage: "photo") { close(); onAlbum() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                action("사진 촬영", systemImage: "camera") { close(); onCamera() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                Color.clear.frame(width: 1, height: 4)
            }
            Button { withAnimation(.spring(duration: 0.3)) { isOpen.toggle() } } label: {
                ZStack {
                    Image("camera-30").opacity(isOpen ? 0 : 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(isOpen ? 1 : 0)
                }
                .frame(width: size, height: size)
                .background(Color.black)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .zoomSource()
            .accessibilityLabel(isOpen ? "닫기" : "판서 올리기")
        }
    }

    private func close() { withAnimation(.easeOut(duration: 0.2)) { isOpen = false } }

    private func action(_ title: String, systemImage: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                Text(title).ds(16, .bold)
            }
            .padding(.leading, 20)
            .padding(.trailing, 22)
            .padding(.vertical, 14)
            .background(Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 펼쳐 있을 때 뒤를 살짝 어둡게. 누르면 닫혀요.
struct CaptureMenuDim: View {
    @Binding var isOpen: Bool

    var body: some View {
        if isOpen {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { isOpen = false } }
                .transition(.opacity)
        }
    }
}

/// 앨범에서 여러 장 고른 뒤 확인 창 (08-2)
/// 사진 빼기 · 길게 눌러 끌어서 순서 바꾸기 · 더 고르기 → `N장 정리하기`
struct AlbumReviewSheet: View {
    @Binding var photos: [UIImage]
    var onMore: () -> Void
    var onCancel: () -> Void
    var onStart: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("사진 \(photos.count)장을 골랐어요").ds(26, .bold)
                    Text("순서대로 정리돼요 · 길게 눌러 끌어서 순서 바꾸기").ds(15, .medium, .dsSub)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                            thumb(photo, index: index)
                        }
                        if photos.count < maxAlbumPhotos { moreButton }
                    }
                    .padding(.vertical, 2)
                }

                Text("자료구조 폴더에 저장").ds(14, .bold, .dsBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.dsBlueSoft, in: Capsule())

                HStack(spacing: 12) {
                    GrayButton(title: "취소", action: onCancel)
                    Button(action: onStart) {
                        Text("\(photos.count)장 정리하기").ds(17, .bold, .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 28)
            .frame(maxWidth: 720, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(20)
        }
    }

    private func thumb(_ photo: UIImage, index: Int) -> some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFill()
            .frame(width: 164, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)").ds(13, .bold, .white)
                    .frame(width: 24, height: 24)
                    .background(Color.dsBlue, in: Circle())
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                Button { withAnimation { _ = photos.remove(at: index) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.black.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("\(index + 1)번 사진 빼기")
            }
            // 길게 눌러 다른 사진 위로 끌어 놓으면 그 자리로 옮겨요.
            .draggable(String(index)) {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: 120, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let from = items.first.flatMap(Int.init), from != index,
                      photos.indices.contains(from) else { return false }
                withAnimation {
                    photos.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
                }
                return true
            }
    }

    private var moreButton: some View {
        Button(action: onMore) {
            Text("+ 더 고르기").ds(14, .bold, .dsSub)
                .frame(width: 120, height: 120)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}
