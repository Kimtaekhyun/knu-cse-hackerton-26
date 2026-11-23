//
//  CameraPreview.swift
//  chalkdrop
//
//  무음 카메라 미리보기. 누른 곳에 초점 · 노출을 맞추고 노란 네모로 잠깐 보여 줘요.
//

import AVFoundation
import SwiftUI

struct CameraPreview: View {
    let camera: SilentCamera
    /// 초점 표시 (화면 좌표)
    @State private var focusPoint: CGPoint?
    @State private var focusID = 0

    var body: some View {
        PreviewLayerView(engine: camera.engine) { layerPoint, devicePoint in
            camera.focus(at: devicePoint)
            focusPoint = layerPoint
            focusID += 1
        }
        .overlay(alignment: .topLeading) {
            if let focusPoint {
                FocusSquare()
                    .id(focusID)
                    .position(focusPoint)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// 누른 곳 표시: 조금 크게 나타났다가 줄어들고 사라져요
private struct FocusSquare: View {
    @State private var scale: CGFloat = 1.35
    @State private var opacity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { scale = 1 }
                withAnimation(.easeIn(duration: 0.4).delay(0.9)) { opacity = 0 }
            }
    }
}

/// AVCaptureVideoPreviewLayer 를 SwiftUI 에 넣는 부분
private struct PreviewLayerView: UIViewRepresentable {
    let engine: CameraEngine
    /// (화면 좌표, 카메라 좌표 0~1)
    let onTap: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        // 미리보기 레이어는 카메라가 한 장만 갖고 있어요. 뷰가 새로 만들어지면(화면 크기 변경) 여기로 옮겨 붙여요
        let view = PreviewUIView(previewLayer: engine.previewLayer)
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGPoint) -> Void
        init(onTap: @escaping (CGPoint, CGPoint) -> Void) { self.onTap = onTap }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewUIView else { return }
            let point = gesture.location(in: view)
            onTap(point, view.previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }

    final class PreviewUIView: UIView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            layer.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            // 다른 뷰로 옮겨 갔다가 돌아왔으면 다시 붙여요
            if previewLayer.superlayer !== layer { layer.addSublayer(previewLayer) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
