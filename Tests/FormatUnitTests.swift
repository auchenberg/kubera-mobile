import XCTest

/// Covers `Format.Unit` and the column-scoped `Format.money`, which exist so a
/// list of figures shares one notation instead of each row picking its own.
final class FormatUnitTests: XCTestCase {
    private func unit(_ amounts: [Double], compact: Bool = true) -> Format.Unit {
        Format.unit(spanning: amounts, compact: compact)
    }

    private func money(_ amount: Double, _ unit: Format.Unit, signed: Bool = false) -> String {
        Format.money(amount, currency: "USD", masked: false, unit: unit, signed: signed)
    }

    // MARK: - Choosing the unit

    func testTheUnitComesFromTheLargestFigure() {
        // The composition breakdown that prompted this: the old per-value rule
        // gave "$860K, $450K, $130K, $74,000, $62,000, $34,000".
        let column = [860_000.0, 450_000, 130_000, 74_000, 62_000, 34_000]
        XCTAssertEqual(unit(column), .thousands)
    }

    func testAColumnLedByMillionsUsesMillions() {
        XCTAssertEqual(unit([1_610_000, 370_000, 74_000]), .millions)
    }

    func testAColumnLedByBillionsUsesBillions() {
        XCTAssertEqual(unit([2_400_000_000, 500_000_000]), .billions)
    }

    func testASmallColumnStaysExact() {
        // Below the same 100,000 floor `money` uses, so a column of small
        // figures is not pushed into a unit a lone figure would not have used.
        XCTAssertEqual(unit([99_000, 4_000, 250]), .exact)
    }

    func testCompactOffAlwaysMeansExact() {
        XCTAssertEqual(unit([2_400_000_000], compact: false), .exact)
    }

    func testNegativesCountAtTheirMagnitude() {
        // Debts are negative and still need the column scaled to them.
        XCTAssertEqual(unit([-1_200_000, 40_000]), .millions)
    }

    func testAnEmptyColumnIsExactRatherThanACrash() {
        XCTAssertEqual(unit([]), .exact)
        XCTAssertEqual(unit([0]), .exact)
    }

    // MARK: - Formatting to a given unit

    func testEveryRowSharesTheChosenUnit() {
        let u = Format.Unit.thousands
        XCTAssertEqual(money(860_000, u), "$860K")
        XCTAssertEqual(money(130_000, u), "$130K")
        XCTAssertEqual(money(74_000, u), "$74.0K")
        XCTAssertEqual(money(34_000, u), "$34.0K")
    }

    func testSignificantFiguresMatchTheStandaloneFormatter() {
        // A value formatted either way must read identically when the units
        // agree, or the same figure would differ between two screens.
        for amount in [860_000.0, 1_240_000, 2_400_000_000] {
            let auto = Format.money(amount, currency: "USD", masked: false, compact: true)
            let column = money(amount, Format.unit(spanning: [amount], compact: true))
            XCTAssertEqual(auto, column, "disagreed on \(amount)")
        }
    }

    func testExactUnitFallsBackToGroupedDigits() {
        XCTAssertEqual(money(74_000, .exact), "$74,000")
    }

    func testSignIsOptedIntoAndNegativesAlwaysShowIt() {
        XCTAssertEqual(money(130_000, .thousands, signed: true), "+$130K")
        XCTAssertEqual(money(130_000, .thousands), "$130K")
        // A negative reads as negative whether or not signs were requested.
        XCTAssertEqual(money(-130_000, .thousands), "-$130K")
        XCTAssertEqual(money(-130_000, .thousands, signed: true), "-$130K")
    }

    func testZeroCarriesNoSignEvenWhenSignsWereRequested() {
        XCTAssertEqual(money(0, .thousands, signed: true), "$0.00K")
    }

    func testPrivacyModeMasksBeforeAnyFormatting() {
        XCTAssertEqual(
            Format.money(860_000, currency: "USD", masked: true, unit: .thousands),
            Format.masked
        )
    }

    func testCurrencySymbolIsHonoured() {
        XCTAssertEqual(
            Format.money(860_000, currency: "EUR", masked: false, unit: .thousands),
            "€860K"
        )
    }
}
