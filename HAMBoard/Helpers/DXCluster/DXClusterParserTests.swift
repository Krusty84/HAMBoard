//
//  DXClusterParserTests.swift
//  HAMBoardTests
//
//  Created by Sedoykin Alexey on 04/03/2026.
//

import SwiftUI
import XCTest
@testable import HAMBoard

/// Parser behavior tests covering both canonical DX lines and tolerant fallbacks
/// needed for heterogeneous cluster implementations.
final class DXClusterParserTests: XCTestCase {

    // MARK: - Spot Parsing

    /// Canonical DXSpider/AR spot format with explicit Zulu suffix.
    func testParseSpotExtractsCoreFields() {
        let line = "DX de G3XYZ:    14023.0  P5ABC        CW 15 dB  QSL via LOTW    0515Z"
        let spot = parseSpot(from: line)

        XCTAssertEqual(spot.freq, 14023.0, accuracy: 0.0001)
        XCTAssertEqual(spot.dx, "P5ABC")
        XCTAssertEqual(spot.spotter, "G3XYZ")
        XCTAssertEqual(spot.comment, "CW 15 dB QSL via LOTW")
        XCTAssertEqual(spot.timeZ, "0515Z")
        XCTAssertEqual(spot.band, "20m")
        XCTAssertEqual(spot.mode, "CW")
    }

    /// Some cluster nodes emit HHMM without `Z`; parser normalizes this to HHMMZ.
    func testParseSpotConvertsPlainHHMMToZuluSuffix() {
        let line = "DX de W1AW: 14074.0 JA1ZLO FT8 CQ TEST 1234"
        let spot = parseSpot(from: line)

        XCTAssertEqual(spot.timeZ, "1234Z")
        XCTAssertEqual(spot.comment, "FT8 CQ TEST")
    }

    /// Guardrail: malformed spot without colon must not crash or misclassify.
    func testParseSpotWithoutColonIsUnknown() {
        let line = "DX de G3XYZ 14023.0 P5ABC TEST 0515Z"
        let message = DXClusterParser.parse(line)

        guard case .unknown(let raw) = message else {
            XCTFail("Expected .unknown for malformed spot line")
            return
        }

        XCTAssertEqual(raw, line)
    }

    /// Guardrail: non-numeric frequency should stay in `.unknown`.
    func testParseSpotWithInvalidFrequencyIsUnknown() {
        let line = "DX de G3XYZ: BADFREQ P5ABC TEST 0515Z"
        let message = DXClusterParser.parse(line)

        guard case .unknown(let raw) = message else {
            XCTFail("Expected .unknown when frequency is invalid")
            return
        }

        XCTAssertEqual(raw, line)
    }

    // MARK: - Non-Spot Message Parsing

    /// WWV reports are routed to announcement stream.
    func testParseWWVLineReturnsWWVMessage() {
        let line = "WWV A=12 K=2 SFI=101"
        let message = DXClusterParser.parse(line)

        guard case .wwv(let text) = message else {
            XCTFail("Expected .wwv message")
            return
        }

        XCTAssertEqual(text, line)
    }

    /// Traditional "to all" cluster announcement.
    func testParseToAllLineReturnsCommentMessage() {
        let line = "to all de K1ABC: Hello world"
        let message = DXClusterParser.parse(line)

        guard case .comment(let text) = message else {
            XCTFail("Expected .comment message")
            return
        }

        XCTAssertEqual(text, line)
    }

    /// AR-style targeted announcement ("To SOLAR ...") should also be routed as comment.
    func testParseToSolarLineReturnsCommentMessage() {
        let line = "To SOLAR de W3XYZ: A=10 K=1"
        let message = DXClusterParser.parse(line)

        guard case .comment(let text) = message else {
            XCTFail("Expected .comment message")
            return
        }

        XCTAssertEqual(text, line)
    }

    /// Unknown lines (login prompts, banners, errors) must remain observable via `.unknown`.
    func testParseUnrecognizedLineReturnsUnknown() {
        let line = "login:"
        let message = DXClusterParser.parse(line)

        guard case .unknown(let raw) = message else {
            XCTFail("Expected .unknown for unrecognized line")
            return
        }

        XCTAssertEqual(raw, line)
    }

    // MARK: - Helpers

    /// Shared helper to keep spot assertions focused on expected field values.
    private func parseSpot(from line: String, file: StaticString = #filePath, line testLine: UInt = #line) -> Spot {
        let message = DXClusterParser.parse(line)
        guard case .spot(let spot) = message else {
            XCTFail("Expected .spot for line: \(line)", file: file, line: testLine)
            fatalError("unreachable")
        }
        return spot
    }
}
