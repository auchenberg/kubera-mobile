import XCTest

final class MonogramTests: XCTestCase {
    private func initials(_ name: String?, email: String? = nil) -> String {
        Monogram.initials(name: name, email: email)
    }

    // MARK: - The ordinary cases

    func testFirstAndLastNameGiveTwoLetters() {
        XCTAssertEqual(initials("Sam Rivera"), "SR")
    }

    func testASingleWordGivesOneLetter() {
        XCTAssertEqual(initials("Sam"), "S")
    }

    func testMiddleNamesAreSkippedRatherThanIncluded() {
        // Three letters would overflow the circle at large type sizes.
        XCTAssertEqual(initials("Sam Quentin Rivera"), "SR")
    }

    func testLowercaseNamesAreUppercased() {
        XCTAssertEqual(initials("sam rivera"), "SR")
    }

    // MARK: - Whitespace

    func testSurroundingAndRepeatedWhitespaceIsIgnored() {
        XCTAssertEqual(initials("  Sam   Rivera  "), "SR")
    }

    func testTabsAndNewlinesSeparateWordsToo() {
        XCTAssertEqual(initials("Sam\tRivera"), "SR")
        XCTAssertEqual(initials("Sam\nRivera"), "SR")
    }

    // MARK: - Punctuation must not eat an initial

    func testPunctuationIsSkippedToReachTheLetter() {
        // Taking each word's first *character* would yield "(R" here, and
        // dropping the non-letter afterwards would yield just "R" — losing the
        // first name's initial entirely.
        XCTAssertEqual(initials("(Sam) Rivera"), "SR")
        XCTAssertEqual(initials("@sam rivera"), "SR")
        XCTAssertEqual(initials("'Sam' \"Rivera\""), "SR")
    }

    func testHyphenatedSurnameUsesItsFirstLetter() {
        XCTAssertEqual(initials("Sam Rivera-Lopez"), "SR")
    }

    // MARK: - Falling back

    func testAnEmptyOrMissingNameFallsBackToTheEmail() {
        XCTAssertEqual(initials(nil, email: "sam@example.com"), "S")
        XCTAssertEqual(initials("", email: "sam@example.com"), "S")
        XCTAssertEqual(initials("   ", email: "sam@example.com"), "S")
    }

    func testANameOfOnlyPunctuationOrDigitsFallsBackToTheEmail() {
        XCTAssertEqual(initials("---", email: "sam@example.com"), "S")
        XCTAssertEqual(initials("1234", email: "sam@example.com"), "S")
    }

    func testAnEmailStartingWithPunctuationStillFindsALetter() {
        XCTAssertEqual(initials(nil, email: "_sam@example.com"), "S")
    }

    func testWithNothingUsableTheMonogramIsStillNotEmpty() {
        // A blank circle reads as a broken avatar rather than as missing data,
        // so there is always a letter.
        XCTAssertEqual(initials(nil, email: nil), "K")
        XCTAssertEqual(initials("", email: ""), "K")
        XCTAssertEqual(initials("...", email: "..."), "K")
    }

    func testTheResultIsNeverEmptyForAnyInputWeCanThinkOf() {
        let inputs: [String?] = [nil, "", " ", "-", "1", "Sam", "Sam Rivera", "🙂", "🙂 🙃"]
        for name in inputs {
            for email in inputs {
                XCTAssertFalse(
                    Monogram.initials(name: name, email: email).isEmpty,
                    "empty monogram for name \(name ?? "nil"), email \(email ?? "nil")"
                )
            }
        }
    }

    // MARK: - Non-Latin scripts

    func testNonLatinNamesKeepTheirOwnLetters() {
        // uppercased() is a no-op for scripts without case, which is correct —
        // the point is that a letter is found at all rather than falling through
        // to "K" as though the name were unusable.
        XCTAssertEqual(initials("سام ريفيرا"), "سر")
        XCTAssertEqual(initials("佐藤 一郎"), "佐一")
    }

    func testEmojiIsNotALetterSoItFallsThrough() {
        XCTAssertEqual(initials("🙂 🙃", email: "sam@example.com"), "S")
    }

    // MARK: - Display name

    func testDisplayNamePrefersTheNameThenTheEmail() {
        XCTAssertEqual(Monogram.displayName(name: "Sam Rivera", email: "sam@example.com"), "Sam Rivera")
        XCTAssertEqual(Monogram.displayName(name: nil, email: "sam@example.com"), "sam@example.com")
        XCTAssertEqual(Monogram.displayName(name: "  ", email: "sam@example.com"), "sam@example.com")
    }

    func testDisplayNameIsTrimmed() {
        XCTAssertEqual(Monogram.displayName(name: "  Sam Rivera\n", email: nil), "Sam Rivera")
    }

    func testDisplayNameFallsBackToALabelRatherThanAnEmptyString() {
        XCTAssertEqual(Monogram.displayName(name: nil, email: nil), "Kubera account")
        XCTAssertEqual(Monogram.displayName(name: "", email: "   "), "Kubera account")
    }
}
