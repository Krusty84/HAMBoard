//
//  DXClusterTelnetConnectorTests.swift
//  HAMBoardTests
//
//  Created by Sedoykin Alexey on 04/03/2026.
//

import SwiftUI
import XCTest
import Network
@testable import HAMBoard

/// Integration-style tests for connector handshake and stream parsing behavior.
/// A local TELNET server fixture is used to validate wire-level behavior deterministically.
final class DXClusterTelnetConnectorTests: XCTestCase {

    // MARK: - Connection / Login

    @MainActor
    /// Verifies profile detection and command bootstrap for AR-Cluster wording/prompts.
    func testConnectSendsCallsignAndARClusterStartupCommands() async throws {
        let server = try LocalTelnetServer()
        try await server.start()

        let connector = DXClusterTelnetConnector(host: "127.0.0.1", port: server.port, callsign: "ub3arm")

        defer {
            connector.disconnect()
            server.stop()
        }

        let connectedExpectation = expectation(description: "Connector reports connected")

        connector.onEvent = { event in
            if case .connected(let callsign) = event {
                XCTAssertEqual(callsign, "UB3ARM")
                connectedExpectation.fulfill()
            }
        }

        connector.connect()

        try await server.waitForClientConnection()
        try await server.send(data: Data("Welcome to AR-Cluster\r\nPlease enter your callsign:\r\narc>\r\n".utf8))
        await fulfillment(of: [connectedExpectation], timeout: 3.0)

        let lines = try await server.waitForReceivedLines(count: 3)
        XCTAssertEqual(lines.first, "UB3ARM")
        XCTAssertTrue(lines.contains("set/dx_announcements"))
        XCTAssertTrue(lines.contains("set/wwv_announcements"))
    }

    @MainActor
    /// Startup commands should be withheld until login appears accepted.
    /// This protects strict nodes where sending startup early can fail the session.
    func testStartupCommandsWaitForLoginConfirmation() async throws {
        let server = try LocalTelnetServer()
        try await server.start()

        let connector = DXClusterTelnetConnector(host: "127.0.0.1", port: server.port, callsign: "ub3arm")

        defer {
            connector.disconnect()
            server.stop()
        }

        connector.connect()
        try await server.waitForClientConnection()
        try await server.send(data: Data("Please enter your callsign:\r\n".utf8))
        try await Task.sleep(nanoseconds: 800_000_000)

        let lines = server.receivedLinesSnapshot()
        XCTAssertTrue(lines.contains("UB3ARM"))
        XCTAssertFalse(lines.contains("set/dx"))
        XCTAssertFalse(lines.contains("set/dx_announcements"))
        XCTAssertFalse(lines.contains("set/wwv_announcements"))
    }

    // MARK: - Incoming Data Parsing

    @MainActor
    /// Verifies packet fragmentation tolerance: a single logical spot split across chunks
    /// must emit exactly one parsed spot event.
    func testIncomingSpotSplitAcrossChunksEmitsSingleSpotMessage() async throws {
        let server = try LocalTelnetServer()
        try await server.start()

        let connector = DXClusterTelnetConnector(host: "127.0.0.1", port: server.port, callsign: "N0CALL")

        defer {
            connector.disconnect()
            server.stop()
        }

        let spotExpectation = expectation(description: "Spot message received")
        var spotMessages = 0

        connector.onEvent = { event in
            if case .message(.spot(let spot)) = event {
                spotMessages += 1
                XCTAssertEqual(spot.dx, "P5ABC")
                XCTAssertEqual(spot.spotter, "G3XYZ")
                spotExpectation.fulfill()
            }
        }

        connector.connect()
        try await server.waitForClientConnection()

        let firstChunk = Data("DX de G3XYZ: 14023.0 P5ABC TEST".utf8)
        let secondChunk = Data(" 0515Z\n".utf8)

        try await server.send(data: firstChunk)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(spotMessages, 0)

        try await server.send(data: secondChunk)

        await fulfillment(of: [spotExpectation], timeout: 3.0)
        XCTAssertEqual(spotMessages, 1)
    }

    @MainActor
    /// Verifies TELNET control bytes are filtered before parser input and that the connector
    /// returns a TELNET negotiation reply (WILL -> DONT in this scenario).
    func testIncomingTelnetControlBytesAreStrippedBeforeParsing() async throws {
        let server = try LocalTelnetServer()
        try await server.start()

        let connector = DXClusterTelnetConnector(host: "127.0.0.1", port: server.port, callsign: "N0CALL")

        defer {
            connector.disconnect()
            server.stop()
        }

        let wwvExpectation = expectation(description: "WWV message received")
        var collectedRawText = ""

        connector.onRawText = { rawText in
            collectedRawText += rawText
        }

        connector.onEvent = { event in
            if case .message(.wwv(let text)) = event {
                XCTAssertEqual(text, "WWV A=12 K=2 SFI=100")
                wwvExpectation.fulfill()
            }
        }

        connector.connect()
        try await server.waitForClientConnection()

        var payload = Data([255, 251, 1])
        payload.append(0)
        payload.append(Data("WWV A=12 K=2 SFI=100\n".utf8))

        try await server.send(data: payload)

        await fulfillment(of: [wwvExpectation], timeout: 3.0)
        try await server.waitForReceivedRawBytes(containing: [255, 254, 1])
        XCTAssertFalse(collectedRawText.contains("\0"))
    }
}

// MARK: - LocalTelnetServer

/// Minimal async TELNET test fixture:
/// - accepts one TCP client
/// - captures both line-based and raw byte traffic
/// - provides polling helpers for deterministic expectations.
private final class LocalTelnetServer: @unchecked Sendable {

    enum ServerError: Error {
        case listenerNotReady
        case missingPort
        case connectionTimeout
        case missingConnection
        case receiveTimeout
    }

    private let queue = DispatchQueue(label: "DXClusterTelnetConnectorTests.LocalTelnetServer")
    private let lock = NSLock()

    private let listener: NWListener
    private var connection: NWConnection?

    private var isReady = false
    /// Raw payload is required for TELNET negotiation assertions.
    private var receivedRawData = Data()
    private var receiveBuffer = ""
    private var receivedLines: [String] = []

    var port: Int {
        lock.withLock {
            guard let port = listener.port else {
                return 0
            }
            return Int(port.rawValue)
        }
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }

            if case .ready = state {
                self.lock.withLock {
                    self.isReady = true
                }
            }
        }

        listener.newConnectionHandler = { [weak self] newConnection in
            guard let self else {
                return
            }

            self.lock.withLock {
                self.connection = newConnection
            }

            newConnection.start(queue: self.queue)
            self.receive(on: newConnection)
        }
    }

    func start() async throws {
        listener.start(queue: queue)

        try await waitUntil(timeout: 3.0) {
            self.lock.withLock {
                self.isReady
            }
        }

        guard port != 0 else {
            throw ServerError.missingPort
        }
    }

    func stop() {
        lock.withLock {
            connection?.cancel()
            connection = nil
        }
        listener.cancel()
    }

    func waitForClientConnection(timeout: TimeInterval = 3.0) async throws {
        try await waitUntil(timeout: timeout) {
            self.lock.withLock {
                self.connection != nil
            }
        }
    }

    func waitForReceivedLines(count: Int, timeout: TimeInterval = 3.0) async throws -> [String] {
        try await waitUntil(timeout: timeout) {
            self.lock.withLock {
                self.receivedLines.count >= count
            }
        }

        return lock.withLock {
            receivedLines
        }
    }

    func receivedLinesSnapshot() -> [String] {
        lock.withLock {
            receivedLines
        }
    }

    func waitForReceivedRawBytes(containing bytes: [UInt8], timeout: TimeInterval = 3.0) async throws {
        let needle = Data(bytes)
        try await waitUntil(timeout: timeout) {
            self.lock.withLock {
                self.receivedRawData.range(of: needle) != nil
            }
        }
    }

    func send(data: Data) async throws {
        let activeConnection = lock.withLock {
            connection
        }

        guard let activeConnection else {
            throw ServerError.missingConnection
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            activeConnection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else {
                return
            }

            if let data, !data.isEmpty {
                let text = String(decoding: data, as: UTF8.self)

                self.lock.withLock {
                    self.receivedRawData.append(data)
                    self.receiveBuffer += text
                    // Keep a simple line protocol view for command assertions.
                    var lines = self.receiveBuffer.components(separatedBy: "\n")
                    self.receiveBuffer = lines.removeLast()

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            self.receivedLines.append(trimmed)
                        }
                    }
                }
            }

            if !isComplete {
                self.receive(on: connection)
            }
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        throw ServerError.receiveTimeout
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
