import Foundation
import TapgoCore

func runScheduleSpecTests(_ t: TestRunner) {
    let cal = Calendar(identifier: .gregorian)
    let tz = TimeZone.current

    // Anchor: 2026-09-05 10:30:00 local time
    var comp = DateComponents()
    comp.year = 2026; comp.month = 9; comp.day = 5
    comp.hour = 10; comp.minute = 30; comp.second = 0
    let now = cal.date(from: comp)!

    // daily @ 09:00 → today already passed → next is tomorrow 09:00
    let daily = ScheduleSpec.daily(hour: 9, minute: 0)
    let dailyNext = daily.nextFire(after: now, lastFired: nil)
    var expectedDaily = comp; expectedDaily.day = 6; expectedDaily.hour = 9; expectedDaily.minute = 0
    let dailyExpected = cal.date(from: expectedDaily)!
    t.expectEqual(dailyNext.map { abs($0.timeIntervalSince(dailyExpected)) < 1.0 }, true,
                  "daily 09:00 after 10:30 same day rolls to tomorrow 09:00")

    // daily @ 14:00 → today still upcoming
    let dailyAfternoon = ScheduleSpec.daily(hour: 14, minute: 0)
    let dailyAfternoonNext = dailyAfternoon.nextFire(after: now, lastFired: nil)
    var expectedAfternoon = comp; expectedAfternoon.hour = 14; expectedAfternoon.minute = 0
    t.expectEqual(dailyAfternoonNext.map { abs($0.timeIntervalSince(cal.date(from: expectedAfternoon)!)) < 1.0 }, true,
                  "daily 14:00 after 10:30 same day lands at today 14:00")

    // oneShot in the past → nil
    let past = ScheduleSpec.oneShot(now.addingTimeInterval(-3600))
    t.expect(past.nextFire(after: now, lastFired: nil) == nil, "oneShot past returns nil (expired)")

    // oneShot in the future → returns that date
    let future = ScheduleSpec.oneShot(now.addingTimeInterval(3600))
    t.expectEqual(future.nextFire(after: now, lastFired: nil)!.timeIntervalSince(now), 3600,
                  "oneShot future returns its date (within 1s)")

    // interval @ 300s, no last fire → returns now + 300
    let interval = ScheduleSpec.interval(seconds: 300)
    let intervalNext = interval.nextFire(after: now, lastFired: nil)
    t.expectEqual(intervalNext!.timeIntervalSince(now), 300, "interval without lastFired returns now + interval (within 1s)")

    // interval @ 300s with lastFired = now-100 → returns now + 200
    let intervalWithFire = interval.nextFire(after: now, lastFired: now.addingTimeInterval(-100))!
    t.expectEqual(intervalWithFire.timeIntervalSince(now), 200, "interval with lastFired 100s ago returns now + 200 (within 1s)")

    // weekly Sat (weekday=7) at 09:00, anchor is Saturday 2026-09-05 (Swift calendar weekday=7)
    let weekly = ScheduleSpec.weekly(weekday: 7, hour: 9, minute: 0)
    let weeklyNext = weekly.nextFire(after: now, lastFired: nil)
    // 2026-09-05 is Saturday; Sat 09:00 already passed today → next is Sat 09-12 09:00
    var expectedWeekly = comp; expectedWeekly.day = 12; expectedWeekly.hour = 9; expectedWeekly.minute = 0
    t.expectEqual(weeklyNext.map { abs($0.timeIntervalSince(cal.date(from: expectedWeekly)!)) < 1.0 }, true,
                  "weekly Sat 09:00 rolls forward 7 days when today already passed")

    // weekly label format
    t.expect(weekly.label.contains("六"), "weekly label uses Chinese weekday character")

    // Codable round-trip
    let cases: [ScheduleSpec] = [
        .oneShot(now),
        .daily(hour: 9, minute: 30),
        .interval(seconds: 1800),
        .weekly(weekday: 1, hour: 18, minute: 45),
    ]
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    for spec in cases {
        let data = try! enc.encode(spec)
        let restored = try! dec.decode(ScheduleSpec.self, from: data)
        t.expectEqual(restored, spec, "ScheduleSpec round-trips: \(spec.label)")
    }
}
