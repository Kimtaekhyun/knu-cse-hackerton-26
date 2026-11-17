//
//  ImagePicking.swift
//  chalkdrop
//
//  사진첩에서 고르기 · 끌어다 놓기로 이미지 한 장을 받는 도구.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// `isPresented` 가 켜지면 사진첩을 열고, 고른 사진을 `onPick` 으로 넘겨요.
    func imagePicker(isPresented: Binding<Bool>, onPick: @escaping (UIImage) -> Void) -> some View {
        modifier(ImagePickerModifier(isPresented: isPresented, onPick: onPick))
    }

    /// 이미지를 끌어다 놓으면 `onDrop` 으로 넘겨요. 끌고 있는 동안 `isTargeted` 가 켜져요.
    func imageDrop(isTargeted: Binding<Bool>, onDrop: @escaping (UIImage) -> Void) -> some View {
        self.onDrop(of: [.image], isTargeted: isTargeted) { providers in
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: UIImage.self) }) else { return false }
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in onDrop(image) }
            }
            return true
        }
    }
}

private struct ImagePickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (UIImage) -> Void
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images)
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onPick(image)
                    }
                    item = nil
                }
            }
    }
}
