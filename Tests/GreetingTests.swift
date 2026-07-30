import XCTest

final class GreetingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(hour: Int, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 7, day: day, hour: hour
        ))!
    }

    // MARK: - Time of day

    func testTimeOfDayBuckets() {
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 2), calendar: calendar).text, "Still up")
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 8), calendar: calendar).text, "Good morning")
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 14), calendar: calendar).text, "Good afternoon")
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 21), calendar: calendar).text, "Good evening")
    }

    func testBucketBoundaries() {
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 5), calendar: calendar).text, "Good morning")
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 11), calendar: calendar).text, "Good morning")
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 12), calendar: calendar).text, "Good afternoon")
        XCTAssertEqual(Greeting.timeOfDay(for: date(hour: 18), calendar: calendar).text, "Good evening")
    }

    // MARK: - Rotation

    func testPhraseIsStableForTheSameHour() {
        let first = Greeting.phrase(for: date(hour: 10), calendar: calendar)
        let second = Greeting.phrase(for: date(hour: 10), calendar: calendar)
        XCTAssertEqual(first, second, "the greeting must not flicker between renders")
    }

    func testRotationVariesAcrossHoursAndDays() {
        let sameDay = Set((0 ..< 24).map { Greeting.phrase(for: date(hour: $0), calendar: calendar).text })
        XCTAssertGreaterThan(sameDay.count, 4, "a day should show several different greetings")

        let acrossDays = Set((1 ... 20).map { Greeting.phrase(for: date(hour: 9, day: $0), calendar: calendar).text })
        XCTAssertGreaterThan(acrossDays.count, 4, "consecutive days should not repeat one greeting")
    }

    func testEveryForeignHelloExplainsItself() {
        for phrase in Greeting.hellos {
            XCTAssertNotNil(phrase.note, "\(phrase.text) needs a translation note")
            XCTAssertFalse(phrase.text.isEmpty)
        }
    }

    // MARK: - Name handling

    func testLineJoinsGreetingAndFirstName() {
        let line = Greeting.line(for: date(hour: 14), name: "Kenneth", calendar: calendar)
        XCTAssertTrue(line.hasSuffix(", Kenneth"), "got \(line)")
    }

    func testFirstNameTakesOnlyTheFirstWord() {
        XCTAssertEqual(Greeting.firstName(from: "Kenneth Auchenberg"), "Kenneth")
    }

    func testGenericPortfolioNamesAreNotTreatedAsPeople() {
        XCTAssertNil(Greeting.firstName(from: "Main portfolio"))
        XCTAssertNil(Greeting.firstName(from: "personal"))
        XCTAssertNil(Greeting.firstName(from: "My money"))
        XCTAssertNil(Greeting.firstName(from: "   "))
        XCTAssertNil(Greeting.firstName(from: nil))
    }

    func testNamelessLineHasNoDanglingComma() {
        let line = Greeting.line(for: date(hour: 14), name: "Main portfolio", calendar: calendar)
        XCTAssertFalse(line.contains(","), "got \(line)")
        XCTAssertFalse(line.hasSuffix(" "))
    }
}
