//
//  PersonMasking.swift
//  chalkdrop
//
//  판서 사진에 찍힌 사람(교수님 · 앞줄 학생)을 올리기 전에 회색으로 가려요 (초상권).
//  iPad 안에서 Apple Vision 으로 처리해서, 사람이 보이는 원본은 서버 · LLM 으로 나가지 않아요.
//
//  얼굴만 흐리면 체형 · 옷으로 알아볼 수 있어서 사람 전체 실루엣을 채워요.
//  가려진 자리는 원래도 판서가 안 보이던 곳이라 판서 정보는 줄지 않아요.
//

import CoreImage
import UIKit
import Vision

nonisolated enum PersonMasking {
    /// 켜져 있는지. 기본은 켜짐 (설정 화면 토글은 아직 없어요)
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "maskPeople") as? Bool ?? true
    }

    /// 사람 자리를 채울 색 (칠판 · 화이트보드 어느 쪽에서도 판서로 오인되지 않는 중간 회색)
    private static let fillColor = CIColor(red: 0.5, green: 0.5, blue: 0.5)
    private static let context = CIContext()

    /// 사람이 있으면 가린 사진, 없으면 원본(긴 변이 `maxSide` 를 넘으면 줄인 사진), 실패하면 원본 그대로.
    /// 메인 스레드 밖에서 해요. M5 Mac 기준 4K 한 장에 30 ms 안팎이에요.
    static func masked(_ image: UIImage, maxSide: CGFloat) async -> UIImage {
        guard isEnabled else { return image }
        return await Task.detached(priority: .userInitiated) {
            (try? mask(image, maxSide: maxSide)) ?? image
        }.value
    }

    private static func mask(_ image: UIImage, maxSide: CGFloat) throws -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        // 사진 방향을 먼저 바로 세워서, 마스크와 사진의 좌표가 어긋나지 않게 해요
        var upright = CIImage(cgImage: cgImage).oriented(CGImagePropertyOrientation(image.imageOrientation))

        // 48MP 같은 큰 앨범 사진은 어차피 업로드 전에 maxSide 로 줄어요. 먼저 줄여서 마스킹하면
        // 원본 크기로 합성하는 낭비가 없어요. 줄인 사진은 한 번만 렌더링해서 Vision · 합성이 같이 써요
        // (지연 계산된 채로 두면 두 번 그려서 오히려 느려져요). 글씨가 뭉개지지 않게 Lanczos 로 줄여요.
        var downscaled: CGImage?
        let longest = max(upright.extent.width, upright.extent.height)
        if longest > maxSide {
            let scaled = upright.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: maxSide / longest, kCIInputAspectRatioKey: 1,
            ])
            guard let rendered = context.createCGImage(scaled, from: scaled.extent.integral) else { return nil }
            downscaled = rendered
            upright = CIImage(cgImage: rendered)
        }
        let extent = upright.extent

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        try VNImageRequestHandler(ciImage: upright).perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }

        // 마스크는 저해상도라 가장자리에 머리카락 · 어깨가 삐져나오지 않게 조금 넓힌 뒤 사진 크기로 늘려요
        let small = CIImage(cvPixelBuffer: buffer)
        let mask = small
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 4])
            .cropped(to: small.extent)
            .transformed(by: CGAffineTransform(scaleX: extent.width / small.extent.width,
                                               y: extent.height / small.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))

        // 사람이 하나도 없으면 다시 그리지 않아요. 줄였으면 줄인 사진을 돌려줘서 업로드에서 또 줄이지 않게 해요
        guard hasPerson(small) else {
            return downscaled.map { UIImage(cgImage: $0, scale: 1, orientation: .up) }
        }

        let fill = CIImage(color: fillColor).cropped(to: extent)
        let output = fill.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: upright,
            kCIInputMaskImageKey: mask,
        ])
        guard let result = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: result, scale: downscaled == nil ? image.scale : 1, orientation: .up)
    }

    /// 마스크에서 가장 밝은 값이 절반을 넘으면 사람이 있다고 봐요
    private static func hasPerson(_ mask: CIImage) -> Bool {
        let maximum = mask.applyingFilter("CIAreaMaximum", parameters: [
            kCIInputExtentKey: CIVector(cgRect: mask.extent),
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(maximum, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return pixel[0] > 127
    }
}

nonisolated private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
