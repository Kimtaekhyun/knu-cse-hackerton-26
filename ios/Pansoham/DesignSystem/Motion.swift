//
//  Motion.swift
//  chalkdrop
//
//  피그마에 든 애니메이션(키프레임 · 이징)을 그대로 옮기기 위한 도구.
//  피그마 타임라인의 "몇 초에 무엇이 어디서 어디로" 를 tween 한 줄로 적어요.
//

import SwiftUI

/// 피그마 이징
enum Ease {
    case linear
    case out        // ease-out      cubic-bezier(0, 0, 0.58, 1)
    case `in`       // ease-in       cubic-bezier(0.42, 0, 1, 1)
    case inOut      // ease-in-out   cubic-bezier(0.42, 0, 0.58, 1)
    case spring     // 살짝 넘쳤다 돌아오는 스프링 (피그마 값표)
    case bounce     // 크게 튀는 스프링 (피그마 값표)

    func value(_ p: Double) -> Double {
        switch self {
        case .linear: return p
        case .out: return Ease.bezier(p, 0, 0, 0.58, 1)
        case .in: return Ease.bezier(p, 0.42, 0, 1, 1)
        case .inOut: return Ease.bezier(p, 0.42, 0, 0.58, 1)
        case .spring: return Ease.table(p, Ease.springTable)
        case .bounce: return Ease.table(p, Ease.bounceTable)
        }
    }

    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func curve(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            if curve(t, x1, x2) < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return curve(t, y1, y2)
    }

    private static func table(_ p: Double, _ values: [Double]) -> Double {
        let position = p * Double(values.count - 1)
        let index = min(Int(position), values.count - 2)
        let rest = position - Double(index)
        return values[index] + (values[index + 1] - values[index]) * rest
    }

    private static let springTable: [Double] = [
        0, 0.0188, 0.0679, 0.1374, 0.2195, 0.308, 0.3978, 0.4856, 0.5686, 0.6452, 0.7142, 0.7753, 0.8283,
        0.8735, 0.9113, 0.9423, 0.9671, 0.9866, 1.0014, 1.0123, 1.0198, 1.0247, 1.0274, 1.0283, 1.0281,
        1.0268, 1.025, 1.0227, 1.0202, 1.0177, 1.0152, 1.0128, 1.0106, 1.0085, 1.0068, 1.0052, 1.0039,
        1.0028, 1.0018, 1.0011, 1.0005, 1, 0.9997, 0.9995, 0.9993, 0.9992, 0.9992, 0.9992, 0.9992, 0.9993, 1,
    ]
    private static let bounceTable: [Double] = [
        0, 0.0985, 0.342, 0.6483, 0.9442, 1.1767, 1.3179, 1.364, 1.3302, 1.2427, 1.1314, 1.0233, 0.9377,
        0.8853, 0.8675, 0.8791, 0.9105, 0.9509, 0.9904, 1.0219, 1.0414, 1.0482, 1.0443, 1.033, 1.0183,
        1.0039, 0.9923, 0.9851, 0.9825, 0.9838, 0.9878, 0.9932, 0.9984, 1.0027, 1.0054, 1.0064, 1.0059,
        1.0045, 1.0025, 1.0006, 0.9991, 0.9981, 0.9977, 0.9978, 0.9983, 0.9991, 0.9998, 1.0003, 1.0007, 1.0008, 1,
    ]
}

/// 시간 `t`(초)가 `start`~`end` 를 지나는 동안 `from` 에서 `to` 로 바뀌는 값.
/// 그 전에는 `from`, 그 뒤에는 `to`.
func tween(_ t: Double, _ from: Double, _ to: Double, _ start: Double, _ end: Double, _ ease: Ease = .out) -> Double {
    if t <= start { return from }
    if t >= end { return to }
    return from + (to - from) * ease.value((t - start) / (end - start))
}

/// 화면이 나타난 뒤 흐른 시간(초)을 알려 주는 틀.
/// `loop` 를 주면 그 길이로 되풀이하고, 없으면 `length` 초 뒤에 멈춰요.
struct Motion<Content: View>: View {
    var loop: Double? = nil
    var length: Double = 2
    @ViewBuilder var content: (Double) -> Content

    @State private var start = Date()
    @State private var done = false

    var body: some View {
        TimelineView(.animation(paused: done)) { context in
            content(time(context.date))
        }
        .task {
            guard loop == nil else { return }
            try? await Task.sleep(for: .seconds(length + 0.1))
            done = true
        }
    }

    private func time(_ now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(start))
        if let loop { return elapsed.truncatingRemainder(dividingBy: loop) }
        return done ? length : min(elapsed, length)
    }
}

extension View {
    /// 아래에서 떠오르며 나타나기 (피그마의 카드 등장: ease-out)
    func entrance(_ shown: Bool, delay: Double, duration: Double, y: CGFloat) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : y)
            .animation(.easeOut(duration: duration).delay(delay), value: shown)
    }
}
