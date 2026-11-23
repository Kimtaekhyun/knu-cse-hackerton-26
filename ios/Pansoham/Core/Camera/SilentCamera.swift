//
//  SilentCamera.swift
//  chalkdrop
//
//  수업 중에 쓰는 무음 카메라 (#78).
//
//  사진 촬영(AVCapturePhotoOutput)은 iOS 가 셔터음을 직접 내고, 한국 판매 기기는 무음 모드여도 소리가 나요.
//  그래서 영상 프레임(AVCaptureVideoDataOutput)을 계속 받다가, 셔터를 누르면 그다음 몇 프레임 중
//  가장 선명한 한 장을 사진으로 써요. 영상 프레임을 가져오는 건 촬영이 아니라서 소리가 나지 않아요.
//

import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// 화면이 보는 카메라 상태. 실제 카메라 작업은 `CameraEngine` 이 별도 줄(큐)에서 해요.
@Observable
final class SilentCamera {
    enum Status: Equatable {
        /// 아직 권한을 묻기 전 · 준비 중
        case idle
        /// 미리보기가 나오는 중
        case running
        /// 카메라 권한을 거부했어요 (설정에서 켜야 해요)
        case denied
        /// 카메라가 없어요 (시뮬레이터 등). 앨범으로 대신해요
        case unavailable
        /// 시스템이 카메라를 잠시 끊었어요 (화면 나눠 쓰기 · 다른 앱이 카메라 사용 등). 풀리면 다시 켜져요 (#140)
        case interrupted
    }

    private(set) var status: Status = .idle
    /// 셔터를 누르고 사진을 고르는 중 (중복 촬영 막기)
    private(set) var isCapturing = false
    /// 지금 배율 (1 = 확대 없음, #138)
    private(set) var zoom: CGFloat = 1
    /// 확대 상한: 3× 와 기기 최대값 중 작은 쪽. 디지털 확대라 너무 키우면 글씨가 흐려져요
    private(set) var maxZoom: CGFloat = 1

    let engine = CameraEngine()
    private var observers: [NSObjectProtocol] = []

    init() {
        // 카메라가 끊기고 다시 이어지는 걸 알아야 미리보기 · 셔터가 멈춘 채로 남지 않아요 (#140)
        let center = NotificationCenter.default
        let session = engine.session
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupted() }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumed() }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            },
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// 화면에 보이는 중인지 (떠난 뒤 끊김이 풀려도 다시 켜지 않게)
    private var wanted = false

    private func interrupted() {
        if status == .running { status = .interrupted }
    }

    private func resumed() {
        guard wanted, status == .interrupted else { return }
        status = .running
    }

    /// 카메라 오류로 멈췄으면 다시 시작
    private func restart() {
        guard wanted else { return }
        Task { await start() }
    }

    /// 화면에 들어올 때: 권한 확인 → 세션 시작
    func start() async {
        wanted = true
        guard engine.hasCamera else {
            status = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        let started = await engine.start()
        guard wanted else { return }
        if started {
            status = .running
        } else if engine.session.isInterrupted {
            // 다른 앱과 함께 띄워 카메라를 못 쓰는 중. 끊김이 풀리면 `resumed()` 가 다시 켜요
            status = .interrupted
        } else {
            status = .unavailable
        }
        // 다시 열면 1× 부터 (#138)
        maxZoom = min(3, engine.maxZoom)
        setZoom(1)
    }

    /// 배율 바꾸기. `animated` 면 부드럽게 (배율 버튼), 아니면 바로 (핀치)
    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        let clamped = min(max(factor, 1), maxZoom)
        zoom = clamped
        engine.zoom(to: clamped, animated: animated)
    }

    /// 화면을 떠날 때 (배터리 · 발열 때문에 꼭 멈춰요)
    func stop() {
        wanted = false
        engine.stop()
        if status == .running || status == .interrupted { status = .idle }
    }

    /// 무음 촬영. 셔터 뒤 몇 프레임 중 가장 선명한 한 장을 돌려줘요.
    func capture() async -> UIImage? {
        guard status == .running, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await engine.captureSharpest()
    }

    /// 미리보기에서 누른 곳에 초점 · 노출 맞추기 (0~1 카메라 좌표)
    func focus(at point: CGPoint) {
        engine.focus(at: point)
    }
}

// MARK: - 카메라 작업 (별도 큐)

/// AVCaptureSession 을 다루는 부분. 모든 세션 작업은 `sessionQueue` 에서,
/// 프레임은 `frameQueue` 에서 받아요. 화면(메인) 쪽에는 async 함수로만 결과를 넘겨요.
nonisolated final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "chalkdrop.camera.session")
    private let frameQueue = DispatchQueue(label: "chalkdrop.camera.frames")
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var configured = false

    /// 선명도 계산 · 이미지 만들기에 쓰는 Core Image (GPU)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    // 아래 세 값은 frameQueue 에서만 읽고 써요.
    /// 셔터 뒤 아직 더 볼 프레임 수 (0 이면 촬영 중 아님)
    private var framesLeft = 0
    /// 지금까지 본 프레임 중 가장 선명한 것
    private var best: (image: CIImage, score: Double)?
    private var finish: ((UIImage?) -> Void)?

    /// 셔터 뒤 몇 프레임을 볼지. 30fps 기준 약 0.2초라 기다리는 느낌은 거의 없어요.
    private let framesPerShot = 6
    /// 미리보기 · 사진의 회전 (아이패드를 돌려도 사진이 똑바로 나오게)
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    /// 미리보기 레이어. 화면 크기가 바뀌어(스플릿 뷰 ↔ 전체 화면) 미리보기 뷰가 새로 만들어져도
    /// 이 한 장을 옮겨 붙여요. 레이어를 새로 만들면 세션 연결이 꼬여 미리보기가 멈춰요 (#140). 메인에서만 써요.
    @MainActor lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        // 찍히는 범위를 그대로 보여 주려고 잘라 내지 않고 비율대로 (남는 곳은 검은 여백)
        layer.videoGravity = .resizeAspect
        attach(layer)
        return layer
    }()

    var hasCamera: Bool { Self.backCamera() != nil }

    private static func backCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// 세션을 만들고 시작해요. 성공하면 true.
    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !self.configured { self.configured = self.configure() }
                if self.configured && !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.configured && self.session.isRunning && !self.session.isInterrupted)
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() -> Bool {
        guard let device = Self.backCamera(),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 스플릿 뷰 · 슬라이드 오버 · 스테이지 매니저로 다른 앱과 함께 띄워도 카메라를 쓸 수 있게 (지원 기기만, #140)
        if session.isMultitaskingCameraAccessSupported { session.isMultitaskingCameraAccessEnabled = true }

        // 판서 글씨가 읽히도록 가장 높은 해상도부터 (4K ≈ 830만 화소)
        for preset in [AVCaptureSession.Preset.hd4K3840x2160, .hd1920x1080, .high] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            break
        }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        // 프레임은 BGRA 로 받고, 늦은 프레임은 버려서 미리보기가 밀리지 않게
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        // 영상 흔들림 보정은 끄기: 켜면 프레임이 잘리고 늦게 나와요
        output.connection(with: .video)?.preferredVideoStabilizationMode = .off

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = false }
        // 탭으로 맞춘 초점이 장면이 바뀌면 다시 자동으로 돌아오게
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.unlockForConfiguration()

        self.device = device
        return true
    }

    /// 미리보기 레이어가 생기면 회전을 맞춰요. (메인에서 한 번만 불러요)
    @MainActor
    private func attach(_ layer: AVCaptureVideoPreviewLayer) {
        guard let device = Self.backCamera() else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotation = coordinator
        apply(coordinator.videoRotationAngleForHorizonLevelPreview, to: layer.connection)
        // 레이어는 카메라가 한 장만 갖고 있어서 `previewLayer` 로 다시 꺼내 써요
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { coordinator, _ in
            DispatchQueue.main.async {
                self.apply(coordinator.videoRotationAngleForHorizonLevelPreview, to: self.previewLayer.connection)
            }
        }
    }

    private func apply(_ angle: CGFloat, to connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// 셔터: 다음 `framesPerShot` 프레임 중 가장 선명한 것을 사진으로
    func captureSharpest() async -> UIImage? {
        // 사진 회전은 셔터 순간의 방향으로 (frameQueue 에 넘기기 전에 메인에서 읽어요)
        let angle = await MainActor.run { rotation?.videoRotationAngleForHorizonLevelCapture ?? 0 }
        return await withCheckedContinuation { continuation in
            frameQueue.async {
                self.best = nil
                self.captureAngle = angle
                self.framesLeft = self.framesPerShot
                self.shotID += 1
                let shot = self.shotID
                self.finish = { continuation.resume(returning: $0) }
                // 카메라가 끊겨 프레임이 안 오면 끝없이 기다리지 않게: 그때까지 본 것 중 가장 선명한 것, 없으면 nil (#140)
                self.frameQueue.asyncAfter(deadline: .now() + Self.shotTimeout) {
                    guard self.shotID == shot, let done = self.finish else { return }
                    let photo = self.best.flatMap { self.render($0.image) }
                    self.framesLeft = 0
                    self.best = nil
                    self.finish = nil
                    done(photo)
                }
            }
        }
    }

    /// 셔터 순간의 회전 각도 (frameQueue 에서만)
    private var captureAngle: CGFloat = 0
    /// 셔터 번호 (시간 제한이 다음 셔터를 끝내지 않게, frameQueue 에서만)
    private var shotID = 0
    /// 셔터 뒤 프레임을 기다리는 최대 시간
    private static let shotTimeout: TimeInterval = 2

    /// 기기가 허용하는 최대 배율
    var maxZoom: CGFloat { device?.maxAvailableVideoZoomFactor ?? 1 }

    /// 확대. 영상 프레임 자체가 확대되므로 미리보기 · 찍힌 사진이 같은 범위예요 (#138)
    func zoom(to factor: CGFloat, animated: Bool) {
        sessionQueue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            let target = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            if animated {
                device.ramp(toVideoZoomFactor: target, withRate: 6)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = target
            }
            device.unlockForConfiguration()
        }
    }

    /// 누른 곳(0~1 카메라 좌표)에 초점 · 노출
    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                // 프로젝터 · 모니터 화면이 하얗게 날아가지 않게 누른 곳 기준으로 노출
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: 프레임 받기 (frameQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard framesLeft > 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        framesLeft -= 1

        let image = CIImage(cvPixelBuffer: pixels)
        let score = sharpness(of: image)
        if best == nil || score > best!.score {
            // 픽셀 버퍼는 카메라가 다시 써야 해서 오래 붙잡지 않게 한 장만 남겨요
            best = (image, score)
        }

        if framesLeft == 0 {
            let photo = best.flatMap { render($0.image) }
            best = nil
            let done = finish
            finish = nil
            done?(photo)
        }
    }

    /// 선명도 점수: 작게 줄인 흑백 이미지의 윤곽선(엣지) 세기 평균. 흔들리면 윤곽이 흐려져 점수가 낮아요.
    private func sharpness(of image: CIImage) -> Double {
        let scale = 480 / max(image.extent.width, 1)
        let small = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 4])
        let average = small.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: small.extent)])

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(average, toBitmap: &pixel, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        return Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])
    }

    /// 고른 프레임을 셔터 순간 방향으로 돌려 UIImage 로
    private func render(_ image: CIImage) -> UIImage? {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: Self.orientation(for: captureAngle))
    }

    /// 회전 각도(0 · 90 · 180 · 270) → 이미지 방향. 프레임은 센서 기준(가로)으로 들어와요.
    private static func orientation(for angle: CGFloat) -> UIImage.Orientation {
        switch Int(angle.rounded()) % 360 {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
    }
}
