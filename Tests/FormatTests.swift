import XCTest

final class FormatTests: XCTestCase {
    // MARK: - millions

    func testMillionsUsesThreeDecimalsAndTheMillionSuffix() {
        XCTAssertEqual(Format.millions(1_234_567.89, currency: "USD", masked: false), "$1.235 Million")
    }

    func testMillionsUsesTheBillionSuffixAboveOneBillion() {
        XCTAssertEqual(Format.millions(1_200_000_000, currency: "USD", masked: false), "$1.200 Billion")
    }

    func testMillionsFallsBackToFullGroupingBelowOneMillion() {
        XCTAssertEqual(Format.millions(54_321, currency: "USD", masked: false), "$54,321")
    }

    func testMillionsKeepsTheSignBeforeTheSymbol() {
        XCTAssertEqual(Format.millions(-1_500_000, currency: "USD", masked: false), "-$1.500 Million")
    }

    func testMillionsRespectsMasking() {
        XCTAssertEqual(Format.millions(1_234_567.89, currency: "USD", masked: true), Format.masked)
        XCTAssertEqual(Format.millions(54_321, currency: "USD", masked: true), "••••••")
    }

    func testMillionsUsesTheCurrencySymbol() {
        XCTAssertEqual(Format.millions(2_500_000, currency: "EUR", masked: false), "€2.500 Million")
    }

    // MARK: - percent

    func testPercentUsesTwoDecimalsBelowATenth() {
        XCTAssertEqual(Format.percent(0.02), "+0.02%")
    }

    func testPercentDropsDecimalsAtAndAboveOneHundred() {
        XCTAssertEqual(Format.percent(107), "+107%")
    }

    func testPercentUsesOneDecimalInBetween() {
        XCTAssertEqual(Format.percent(12.34), "+12.3%")
    }

    func testPercentDropsTrailingZerosOnWholeNumbers() {
        XCTAssertEqual(Format.percent(-27), "-27%")
        XCTAssertEqual(Format.percent(0), "0%")
    }

    func testPercentWithoutSigningDropsThePlus() {
        XCTAssertEqual(Format.percent(12.34, signed: false), "12.3%")
        XCTAssertEqual(Format.percent(-27, signed: false), "-27%")
    }
}
