import XCTest
import HealthKit
@testable import IronForge

final class HealthKitHelpersTests: XCTestCase {
    func testPermissionStateMapping() {
        XCTAssertEqual(HealthKitService.permissionState(from: .notDetermined), .notDetermined)
        XCTAssertEqual(HealthKitService.permissionState(from: .sharingDenied), .denied)
        XCTAssertEqual(HealthKitService.permissionState(from: .sharingAuthorized), .authorized)
    }
    
    func testBucketedMinutesByDaySplitsAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 0))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 1, minute: 0))!
        
        let result = HealthKitDateHelpers.bucketedMinutesByDay(segments: [(start: start, end: end)], calendar: calendar)
        
        let day1 = calendar.startOfDay(for: start)
        let day2 = calendar.startOfDay(for: end)
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[day1], 60, accuracy: 0.0001)
        XCTAssertEqual(result[day2], 60, accuracy: 0.0001)
    }
}

