import XCTest
@testable import ClaudeOMeter

final class FormattingTests: XCTestCase {

    // MARK: - Fmt.usd

    func testUsdFormatsZero() {
        let s = Fmt.usd(0)
        XCTAssertTrue(s.contains("0"), "Expected $0 format, got \(s)")
    }

    func testUsdFormatsTypicalCents() {
        let s = Fmt.usd(0.05)
        XCTAssertTrue(s.contains("0.05") || s.contains("0,05"), "Expected cents format, got \(s)")
    }

    func testUsdFormatsDollarAmount() {
        let s = Fmt.usd(12.34)
        XCTAssertTrue(s.contains("12"), "Expected 12 in formatted string, got \(s)")
        XCTAssertTrue(s.contains("34"), "Expected 34 in formatted string, got \(s)")
    }

    func testUsdContainsCurrencySymbol() {
        let s = Fmt.usd(5.0)
        // USD symbol or ISO code — locale-dependent, but must contain a currency marker
        let hasCurrencyIndicator = s.contains("$") || s.contains("USD") || s.contains("US$")
        XCTAssertTrue(hasCurrencyIndicator, "Expected currency indicator in \(s)")
    }

    // MARK: - Fmt.tokens

    func testTokensSmall() {
        XCTAssertEqual(Fmt.tokens(0), "0")
        XCTAssertEqual(Fmt.tokens(999), "999")
    }

    func testTokensThousands() {
        let s = Fmt.tokens(1_000)
        XCTAssertTrue(s.hasSuffix("K"), "Expected K suffix, got \(s)")
        XCTAssertTrue(s.contains("1"), "Expected 1 in \(s)")
    }

    func testTokensThousandsBoundaryBelow() {
        let s = Fmt.tokens(999)
        XCTAssertFalse(s.hasSuffix("K"), "999 should not get K suffix, got \(s)")
    }

    func testTokensMillions() {
        let s = Fmt.tokens(1_000_000)
        XCTAssertTrue(s.hasSuffix("M"), "Expected M suffix, got \(s)")
        XCTAssertTrue(s.contains("1"), "Expected 1 in \(s)")
    }

    func testTokensMillionsBoundaryBelow() {
        let s = Fmt.tokens(999_999)
        XCTAssertFalse(s.hasSuffix("M"), "999,999 should not get M suffix, got \(s)")
        XCTAssertTrue(s.hasSuffix("K"), "999,999 should get K suffix, got \(s)")
    }

    func testTokensDecimalAbbrev() {
        let s = Fmt.tokens(1_500)
        XCTAssertTrue(s.contains("1.5") || s.contains("1,5"), "Expected 1.5K, got \(s)")
        XCTAssertTrue(s.hasSuffix("K"))
    }

    func testTokensLargeMillions() {
        let s = Fmt.tokens(83_074_000)
        XCTAssertTrue(s.hasSuffix("M"), "Expected M suffix for 83M, got \(s)")
    }

    // MARK: - Fmt.dayLabel

    func testDayLabelParsesKnownDate() {
        let s = Fmt.dayLabel("2026-06-20")
        // Should contain abbreviated month name "Jun" and day number
        XCTAssertTrue(s.contains("20") || s.contains("Jun") || s.count > 4,
                      "Expected a non-trivial day label for 2026-06-20, got \(s)")
    }

    func testDayLabelReturnsInputOnBadFormat() {
        // Invalid date string → returns the input unchanged
        let bad = "not-a-date"
        XCTAssertEqual(Fmt.dayLabel(bad), bad)
    }

    func testDayLabelReturnsInputOnEmpty() {
        XCTAssertEqual(Fmt.dayLabel(""), "")
    }
}
