//
//  SampleData.swift
//  chalkdrop
//
//  피그마 와이어프레임에 적힌 예시 값. 나중에 진짜 데이터로 바꾸면 돼요.
//

import UIKit

struct TimetableSubject: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var time: String
}

enum SampleData {
    static let timetable: [TimetableSubject] = [
        .init(name: "자료구조", time: "월 10:30–12:00"),
        .init(name: "컴퓨터구조", time: "화 13:00–14:30"),
        .init(name: "확률과 통계", time: "수 09:00–10:30"),
        .init(name: "이산수학", time: "목 15:00–16:30"),
        .init(name: "운영체제", time: "금 10:30–12:00"),
    ]
}

/// 판서에서 찾아낸 카드 한 장
struct Sticker: Identifiable, Hashable {
    var id: Int                 // 카드 번호 (1부터)
    let title: String
    let kind: String            // "수식" 등
    let text: String            // 텍스트로 바꾼 내용
    /// 원본 사진(372 × 279 기준)에서 이 카드가 차지하는 자리
    var x: CGFloat = 204.6, y: CGFloat = 36.27, w: CGFloat = 159.96, h: CGFloat = 100.44
    var handwriting = false     // 처음부터 손글씨로 보여 줄지
    var inkImage: String? = nil // 손글씨 그림이 따로 있으면 그 이름
    /// 서버에서 받은 판서 사진 (없으면 샘플 사진 `board-photo`). 자리는 너비 372 · 높이 372 × photoAspect 기준
    var photo: UIImage? = nil
    var photoAspect: CGFloat = 279.0 / 372.0
    /// 서버 카드 id (샘플이면 nil, #99)
    var cardID: UUID? = nil
    /// text · math · code
    var cardType = "text"
    /// 사용자가 고쳤는지 (원래대로 되돌리기)
    var isEdited = false
}

extension SampleData {
    static let stickers: [Sticker] = [
        .init(id: 1, title: "f(x) 정의 · 도함수", kind: "수식",
              text: "f(x) = ln x / x\nf′(x) = (1 − ln x) / x² < 0",
              x: 18.6, y: 145.08, w: 174.84, h: 69.75),
        .init(id: 2, title: "극한 계산", kind: "수식",
              text: "lim ln x / x = lim 1 / x = 0",
              x: 204.6, y: 36.27, w: 159.96, h: 100.44, handwriting: true),
        .init(id: 3, title: "적분 풀이 → 발산", kind: "수식",
              text: "∫₃^∞ (ln x / x) dx\n= ½[(ln x)²]₃^∞ = ∞",
              x: 204.6, y: 161.82, w: 159.96, h: 106.02),
        .init(id: 4, title: "부등식 → x > e", kind: "수식",
              text: "1 − ln x < 0  →  x > e",
              x: 18.6, y: 223.2, w: 148.8, h: 47.43),
    ]
}

extension SampleData {
    /// 16 카드 모아 보기 — 자료구조 과목의 카드
    static let subjectStickers: [Sticker] = [
        .init(id: 1, title: "스택의 연산", kind: "텍스트", text: "push(x): top ← top + 1\npop(): top ← top − 1"),
        .init(id: 2, title: "분할 정복 점화식", kind: "수식", text: "T(n) = 2T(n/2) + O(n)",
              handwriting: true, inkImage: "ink-formula"),
        .init(id: 3, title: "결론", kind: "수식", text: "T(n) = O(n log n)"),
        .init(id: 4, title: "원형 큐 인덱스", kind: "수식", text: "rear ← (rear + 1) mod n"),
        .init(id: 5, title: "예시 코드", kind: "코드", text: "stack.push(3)\nstack.push(5)\nstack.pop()  # 5"),
        .init(id: 6, title: "큐의 연산", kind: "텍스트", text: "enqueue: 뒤에 넣기\ndequeue: 앞에서 빼기"),
        .init(id: 7, title: "오버플로 조건", kind: "수식", text: "(rear + 1) mod n = front"),
        .init(id: 8, title: "덱", kind: "텍스트", text: "양쪽 끝에서 넣고 빼기"),
        .init(id: 9, title: "주의", kind: "텍스트", text: "빈 스택에서 pop → underflow"),
    ]
}
