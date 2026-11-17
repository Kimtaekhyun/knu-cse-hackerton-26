//
//  CaptureDefaults.swift
//  판서함
//
//  내 계정(23)에서 고르는 기본 촬영 모드 · 펜 색. 촬영 화면(09)이 처음 열릴 때 이 값으로 시작해요.
//

enum CaptureDefaults {
    static let modeKey = "defaultCaptureMode"
    static let penKey = "defaultPenColor"
    /// 촬영 화면 `mode` 순서와 같아요.
    static let modes = ["빔 화면", "칠판"]
    /// 촬영 화면 `pen` 순서와 같아요.
    static let pens = ["빨간 펜", "검은 펜"]
}
