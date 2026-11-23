//
//  LocalNotifications.swift
//  chalkdrop
//
//  로컬 알림 (#125). 서버 푸시 없이 앱이 UNUserNotificationCenter 로 예약해요.
//  1. 수업 후 정리: 판서를 찍은 수업이 끝나고 5분 뒤 → 그 과목 폴더
//  2. 시험 복습: 시험 시작 7일 전 · 1일 전 오전 9시 → 메인
//  3. 미분류함: 미분류 판서가 남아 있으면 그날 21시 → 미분류함
//  스위치: "정리 알림"(notify_unmoved) = 1 · 3, "시험 기간 알림"(notify_exam) = 2
//

import SwiftUI
import UserNotifications

@MainActor
@Observable
final class LocalNotifications: NSObject {
    static let shared = LocalNotifications()

    /// 알림을 눌러 열 화면 (ContentView 가 보고 이동해요)
    enum Route: Equatable { case subject(UUID), home, unsorted }
    var pendingRoute: Route?

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private static let cleanupKey = "notifyCleanup"
    private static let examKey = "notifyExam"
    private static let askedKey = "notifyAsked"

    /// 스위치 값 (서버 설정을 기기에도 둬요)
    var cleanupOn: Bool { defaults.object(forKey: Self.cleanupKey) as? Bool ?? true }
    var examOn: Bool { defaults.object(forKey: Self.examKey) as? Bool ?? true }

    // MARK: 권한 · 설정

    /// 로그인 직후 한 번만 물어봐요
    func requestOnce() {
        guard !defaults.bool(forKey: Self.askedKey) else { return }
        defaults.set(true, forKey: Self.askedKey)
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 사용자가 알림을 거절했는지
    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// 서버 설정을 받아 기기에 두고, 끈 알림은 예약을 지워요
    func apply(cleanup: Bool, exam: Bool) {
        defaults.set(cleanup, forKey: Self.cleanupKey)
        defaults.set(exam, forKey: Self.examKey)
        Task {
            if !cleanup { await remove { $0.hasPrefix("class-") || $0.hasPrefix("unsorted-") } }
            if !exam { await remove { $0.hasPrefix("exam-") } }
        }
    }

    /// 로그아웃 · 토큰 만료: 예약을 모두 지워요 (다른 사용자에게 남지 않게)
    nonisolated static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: 1. 수업 후 정리

    /// 판서를 찍었을 때: 지금 수업 중이면 그 수업 끝 + 5분에 예약 (같은 날 같은 수업은 한 번, 판서 수만 갱신)
    func noteCaptured(count: Int, at date: Date = .now) {
        guard cleanupOn, count > 0, let (subject, end) = classAt(date) else { return }
        let fire = end.addingTimeInterval(5 * 60)
        guard fire > .now else { return }
        let id = "class-\(subject.id.uuidString)-\(Self.day(date))"
        let total = defaults.integer(forKey: id) + count
        defaults.set(total, forKey: id)
        schedule(id: id, title: "\(subject.name) 수업 끝 · 오늘 판서 \(total)장",
                 body: "노트에 옮겨 두면 복습할 때 편해요",
                 route: "subject:\(subject.id.uuidString)", at: fire)
    }

    /// "아직 옮기지 않은 판서"를 새로 받았을 때: 오늘 그 수업 판서를 모두 옮겼으면 예약 취소
    func unmovedChanged(_ items: [SubjectCaptures.Item]) {
        let today = Self.day(.now)
        let left = Set(items.filter { $0.capture.classDate == today }.compactMap(\.capture.subjectId))
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier)
            let done = pending.filter { id in
                guard id.hasPrefix("class-"), id.hasSuffix(today) else { return false }
                let uuid = UUID(uuidString: String(id.dropFirst(6).prefix(36)))
                return uuid.map { !left.contains($0) } ?? false
            }
            center.removePendingNotificationRequests(withIdentifiers: done)
        }
    }

    /// 시간표에서 `date`에 진행 중인 수업과 끝나는 시각
    private func classAt(_ date: Date) -> (SemesterAPI.SubjectDTO, Date)? {
        let calendar = Calendar.current
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7   // 0 = 월
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        for subject in SemesterStore.shared.subjects {
            for slot in subject.slots where slot.weekday == weekday {
                let start = Self.minutes(slot.start), end = Self.minutes(slot.end)
                guard start <= minute, minute < end else { continue }
                let endDate = calendar.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: date) ?? date
                return (subject, endDate)
            }
        }
        return nil
    }

    // MARK: 2. 시험 복습

    /// 메인 값을 받았을 때: 다가오는 시험의 D-7 · D-1 오전 9시 (지난 시각은 건너뛰고, 시험이 없으면 취소)
    func scheduleExam(_ exam: HomeAPI.ExamDTO?, captures: Int) {
        Task {
            await remove { $0.hasPrefix("exam-") }
            guard examOn, let exam, !exam.inProgress, let starts = exam.startDate else { return }
            for days in [7, 1] {
                guard let day = Calendar.current.date(byAdding: .day, value: -days, to: starts),
                      let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                      fire > .now else { continue }
                schedule(id: "exam-\(exam.kind)-d\(days)",
                         title: "\(exam.title) D-\(days) · 이번 학기 판서 \(captures)장을 모아 뒀어요",
                         body: "과목 폴더에서 카드를 모아 보세요", route: "home", at: fire)
            }
        }
    }

    // MARK: 3. 미분류함

    /// 미분류 목록을 받았을 때: 남아 있으면 그날 21시(지났으면 다음 날), 0장이면 취소
    func unsortedChanged(count: Int) {
        Task {
            await remove { $0.hasPrefix("unsorted-") }
            guard cleanupOn, count > 0 else { return }
            let calendar = Calendar.current
            var fire = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
            if fire <= .now { fire = calendar.date(byAdding: .day, value: 1, to: fire) ?? fire }
            schedule(id: "unsorted-\(Self.day(fire))", title: "과목을 정하지 않은 판서 \(count)장이 있어요",
                     body: "미분류함에서 과목을 정해 주세요", route: "unsorted", at: fire)
        }
    }

    // MARK: 시연 (-notifyDemo)

    /// 세 알림을 지금 데이터로 10초 간격으로 띄워요
    func demo() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let subject = SemesterStore.shared.subjects.first
        let name = subject?.name ?? "자료구조"
        let total = SemesterStore.shared.subjects.map(\.captureCount).reduce(0, +)
        let unsorted = SubjectCaptures.unsorted.items.count
        let exam = HomeStore.shared.home?.exam
        schedule(id: "demo-class", title: "\(name) 수업 끝 · 오늘 판서 3장", body: "노트에 옮겨 두면 복습할 때 편해요",
                 route: subject.map { "subject:\($0.id.uuidString)" } ?? "home", after: 10)
        schedule(id: "demo-exam", title: "\(exam?.title ?? "기말") D-7 · 이번 학기 판서 \(max(total, 48))장을 모아 뒀어요",
                 body: "과목 폴더에서 카드를 모아 보세요", route: "home", after: 20)
        schedule(id: "demo-unsorted", title: "과목을 정하지 않은 판서 \(max(unsorted, 2))장이 있어요",
                 body: "미분류함에서 과목을 정해 주세요", route: "unsorted", after: 30)
    }

    // MARK: 도구

    private func schedule(id: String, title: String, body: String, route: String, at date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        add(id: id, title: title, body: body, route: route,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    private func schedule(id: String, title: String, body: String, route: String, after seconds: TimeInterval) {
        add(id: id, title: title, body: body, route: route,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
    }

    /// 같은 id 로 다시 예약하면 이전 예약이 바뀌어요
    private func add(id: String, title: String, body: String, route: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": route]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func remove(where match: (String) -> Bool) async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter(match)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func minutes(_ text: String) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }
}

// MARK: - 앱을 쓰는 중에도 배너 · 누르면 화면 이동

extension LocalNotifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String ?? "home"
        await MainActor.run {
            if route == "unsorted" {
                pendingRoute = .unsorted
            } else if route.hasPrefix("subject:"), let id = UUID(uuidString: String(route.dropFirst(8))) {
                pendingRoute = .subject(id)
            } else {
                pendingRoute = .home
            }
        }
    }
}
