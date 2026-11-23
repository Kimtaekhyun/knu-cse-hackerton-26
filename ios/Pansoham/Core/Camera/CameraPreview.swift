//
//  CameraPreview.swift
//  chalkdrop
//
//  무음 카메라 미리보기. 누른 곳에 초점 · 노출을 맞추고 노란 네모로 잠깐 보여 줘요.
//  두 손가락으로 벌리면 확대, 아래 배율 버튼(1× · 2× · 3×)으로도 바꿔요 (#138).
//

import AVFoundation
import SwiftUI

struct CameraPreview: View {
    let camera: SilentCamera
    /// 초점 표시 (화면 좌표)
    @State private var focusPoint: CGPoint?
    @State private var focusID = 0
    /// 핀치를 시작할 때 배율
    @State private var pinchBase: CGFloat = 1

    var body: some View {
        PreviewLayerView(engine: camera.engine, onTap: { layerPoint, devicePoint in
            camera.focus(at: devicePoint)
            focusPoint = layerPoint
            focusID += 1
        }, onPinch: { scale, began in
            if began { pinchBase = camera.zoom }
            camera.setZoom(pinchBase * scale)
        })
        .overlay(alignment: .bottom) {
            if camera.maxZoom > 1 {
                ZoomBar(camera: camera).padding(.bottom, 24)
            }
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

/// 배율 버튼: 1× · 2× · 3× (기기 최대값 안쪽만). 고른 칸은 크고 노란 글자, 핀치 중엔 지금 배율("1.8×")
private struct ZoomBar: View {
    let camera: SilentCamera
    private let presets: [CGFloat] = [1, 2, 3]

    var body: some View {
        let shown = presets.filter { $0 <= camera.maxZoom + 0.01 }
        // 지금 배율이 속한 칸 (가장 가까운 아래 칸)
        let active = shown.last { $0 <= camera.zoom + 0.05 } ?? 1
        HStack(spacing: 6) {
            ForEach(shown, id: \.self) { preset in
                let on = preset == active
                Button { camera.setZoom(preset, animated: true) } label: {
                    Text(on ? Self.label(camera.zoom) : Self.label(preset))
                        .font(.system(size: on ? 15 : 13, weight: .bold))
                        .foregroundStyle(on ? Color.yellow : .white)
                        .frame(width: on ? 48 : 38, height: on ? 48 : 38)
                        .background(Color.black.opacity(on ? 0.6 : 0.35), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.45), in: Capsule())
        .animation(.easeOut(duration: 0.15), value: active)
    }

    /// 1 → "1×", 1.8 → "1.8×"
    private static func label(_ zoom: CGFloat) -> String {
        let rounded = (zoom * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))×" : String(format: "%.1f×", rounded)
    }
}

/// AVCaptureVideoPreviewLayer 를 SwiftUI 에 넣는 부분
private struct PreviewLayerView: UIViewRepresentable {
    let engine: CameraEngine
    /// (화면 좌표, 카메라 좌표 0~1)
    let onTap: (CGPoint, CGPoint) -> Void
    /// (시작부터 벌린 비율, 막 시작했는지)
    let onPinch: (CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = engine.session
        // 찍히는 범위를 그대로 보여 주려고 잘라 내지 않고 비율대로 (남는 곳은 검은 여백)
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        engine.attach(view.previewLayer)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        // 한 손가락 탭 = 초점, 두 손가락 = 확대
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched(_:)))
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onPinch = onPinch
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap, onPinch: onPinch) }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGPoint) -> Void
        var onPinch: (CGFloat, Bool) -> Void
        init(onTap: @escaping (CGPoint, CGPoint) -> Void, onPinch: @escaping (CGFloat, Bool) -> Void) {
            self.onTap = onTap
            self.onPinch = onPinch
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began: onPinch(gesture.scale, true)
            case .changed: onPinch(gesture.scale, false)
            default: break
            }
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewUIView else { return }
            let point = gesture.location(in: view)
            onTap(point, view.previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
