//
//  DXClusterTelnetConnector.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 27/02/2026.
//

import SwiftUI
import Foundation
import Network

/// Resilient Telnet connector for multiple DX cluster families (DXSpider, AR-Cluster, CC Cluster).
///
/// The connector intentionally separates transport, handshake, and line parsing:
/// 1. Maintain a single TCP stream and parse TELNET control bytes/statefully.
/// 2. Negotiate login and startup commands using prompt + timeout fallbacks.
/// 3. Emit clean text lines to `DXClusterParser` for protocol-level message parsing.
@MainActor
final class DXClusterTelnetConnector {

    // MARK: - Event

    enum Event {
        case connecting(host: String, port: Int)
        case connected(callsign: String)
        case message(ClusterMessage)
        case failed(description: String)
        case disconnectedByRemote
        case disconnected
    }

    /// Runtime cluster profile used to choose startup commands.
    /// `unknown` intentionally uses a compatibility superset.
    private enum ClusterFlavor {
        case unknown
        case dxSpider
        case arCluster
        case ccCluster
    }

    /// Stateful TELNET parser to safely handle control sequences split across packets.
    /// This avoids corrupting line payload when IAC/negotiation arrives chunked.
    private enum TelnetParserState {
        case data
        case iac
        case negotiation(command: UInt8)
        case subnegotiation
        case subnegotiationIAC
    }

    private enum TelnetByte {
        static let se: UInt8 = 240
        static let sb: UInt8 = 250
        static let will: UInt8 = 251
        static let wont: UInt8 = 252
        static let `do`: UInt8 = 253
        static let dont: UInt8 = 254
        static let iac: UInt8 = 255
    }

    // MARK: - Public Callback

    var onEvent: ((Event) -> Void)?
    var onRawText: ((String) -> Void)?

    // MARK: - Configuration

    private let host: String
    private let port: Int
    private let callsign: String

    // MARK: - Connection State

    private var connection: NWConnection?
    private var buffer = ""
    private var isCancelled = false
    private let parsingQueue = DispatchQueue(
        label: "HAMBoard.DXClusterTelnetConnector.ParsingQueue",
        qos: .userInitiated
    )
    /// Handshake gates:
    /// - login must be sent once (plus optional retry)
    /// - startup commands must be sent once per session.
    private var hasSentLogin = false
    private var isLoginConfirmed = false
    private var hasSentStartupCommands = false
    /// Used for login retry heuristic: if server stays silent after login, retry callsign once.
    private var receivedServerLineCount = 0
    private var loginLineBaseline = 0
    private var clusterFlavor: ClusterFlavor = .unknown
    private var telnetParserState: TelnetParserState = .data
    /// Prevent duplicate startup commands when mixed flavor fallbacks are active.
    private var sentStartupCommands = Set<String>()
    private var loginFallbackTask: Task<Void, Never>?
    private var loginRetryTask: Task<Void, Never>?
    private var startupFallbackTask: Task<Void, Never>?

    // MARK: - Initialization

    init(host: String, port: Int, callsign: String) {
        self.host = DXClusterConfigurationRepository.normalizedHost(host)
        self.port = port
        let normalizedCallsign = callsign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.callsign = normalizedCallsign.isEmpty ? "NOCALL" : normalizedCallsign
    }

    // MARK: - Public API

    /// Starts a new Telnet session. Any previous connection state is discarded.
    func connect() {
        connection?.cancel()
        connection = nil

        isCancelled = false
        resetRuntimeState()
        onEvent?(.connecting(host: host, port: port))

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            Task { @MainActor in
                guard let self, let activeConnection = conn else {
                    return
                }
                self.handleConnectionState(state, on: activeConnection)
            }
        }

        conn.start(queue: .global())
    }

    func disconnect() {
        isCancelled = true
        cancelRuntimeTasks()
        connection?.cancel()
        connection = nil
    }

    /// Sends a raw command line to the cluster using TELNET-compatible CRLF framing.
    func sendCommand(_ command: String) {
        guard let activeConnection = connection, !isCancelled else {
            return
        }

        send(command, on: activeConnection)
    }

    // MARK: - Connection Lifecycle

    /// Handles low-level network state and kicks off handshake receive/login fallback.
    private func handleConnectionState(_ state: NWConnection.State, on activeConnection: NWConnection) {
        guard connection === activeConnection else {
            return
        }

        switch state {
        case .ready:
            onEvent?(.connected(callsign: callsign))
            receive(on: activeConnection)
            scheduleLoginFallback(on: activeConnection, delayNanoseconds: 300_000_000)
        case .failed(let error):
            cancelRuntimeTasks()
            onEvent?(.failed(description: error.localizedDescription))
            connection = nil
        case .cancelled:
            cancelRuntimeTasks()
            if isCancelled {
                onEvent?(.disconnected)
            }
            connection = nil
        default:
            break
        }
    }

    private func send(_ text: String, on connection: NWConnection) {
        // Telnet-compatible line ending for broad cluster compatibility.
        let line = text.trimmingCharacters(in: .newlines) + "\r\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        connection.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self else {
                return
            }

            Task { @MainActor in
                guard !self.isCancelled else {
                    return
                }

                guard let connection else {
                    return
                }

                guard self.connection === connection else {
                    return
                }

                if let error {
                    self.cancelRuntimeTasks()
                    self.onEvent?(.failed(description: error.localizedDescription))
                    self.connection?.cancel()
                    self.connection = nil
                    return
                }

                if let data {
                    let receivedText = self.decodeTextChunk(data, on: connection)
                    if !receivedText.isEmpty {
                        self.onRawText?(receivedText)
                        self.process(receivedText, on: connection)
                    }
                }

                if isComplete {
                    self.cancelRuntimeTasks()
                    self.onEvent?(.disconnectedByRemote)
                    self.connection?.cancel()
                    self.connection = nil
                    return
                }

                if !self.isCancelled {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func decodeTextChunk(_ data: Data, on connection: NWConnection) -> String {
        let parsedPayload = parsedTelnetPayload(from: data)

        // Reply to TELNET option negotiation immediately to keep servers in text mode.
        for response in parsedPayload.negotiationResponses {
            connection.send(content: response, completion: .contentProcessed({ _ in }))
        }

        let sanitizedBytes = parsedPayload.payload
        guard !sanitizedBytes.isEmpty else {
            return ""
        }

        // Preserve printable payload even when chunks include non-UTF8 control bytes.
        return String(decoding: sanitizedBytes, as: UTF8.self)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    private func parsedTelnetPayload(from data: Data) -> (payload: Data, negotiationResponses: [Data]) {
        let bytes = Array(data)
        guard !bytes.isEmpty else {
            return (Data(), [])
        }

        var sanitized: [UInt8] = []
        sanitized.reserveCapacity(bytes.count)

        var responses: [Data] = []
        responses.reserveCapacity(4)

        // Single-pass TELNET state machine:
        // - strips control bytes from payload
        // - preserves escaped IAC (255 255)
        // - collects negotiation replies (DO/DONT/WILL/WONT).
        for byte in bytes {
            switch telnetParserState {
            case .data:
                if byte == TelnetByte.iac {
                    telnetParserState = .iac
                } else if byte != 0 {
                    sanitized.append(byte)
                }

            case .iac:
                switch byte {
                case TelnetByte.iac:
                    sanitized.append(TelnetByte.iac)
                    telnetParserState = .data
                case TelnetByte.sb:
                    telnetParserState = .subnegotiation
                case TelnetByte.do, TelnetByte.dont, TelnetByte.will, TelnetByte.wont:
                    telnetParserState = .negotiation(command: byte)
                default:
                    telnetParserState = .data
                }

            case .negotiation(let command):
                if let response = telnetNegotiationResponse(command: command, option: byte) {
                    responses.append(Data(response))
                }
                telnetParserState = .data

            case .subnegotiation:
                if byte == TelnetByte.iac {
                    telnetParserState = .subnegotiationIAC
                }

            case .subnegotiationIAC:
                if byte == TelnetByte.se {
                    telnetParserState = .data
                } else if byte == TelnetByte.iac {
                    telnetParserState = .subnegotiation
                } else {
                    telnetParserState = .subnegotiation
                }
            }
        }

        return (Data(sanitized), responses)
    }

    private func process(_ text: String, on connection: NWConnection) {
        // Normalize line endings because cluster implementations differ (\n, \r\n, \r).
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        buffer += normalized
        var lines = buffer.components(separatedBy: "\n")
        buffer = lines.removeLast()
        var linesToParse: [String] = []
        linesToParse.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            receivedServerLineCount += 1
            updateClusterFlavor(with: trimmed)
            updateLoginState(with: trimmed)
            maybeTriggerLogin(from: trimmed, on: connection)
            linesToParse.append(trimmed)

            // Once login was attempted, send startup filters exactly once.
            if hasSentLogin {
                sendStartupCommandsIfNeeded(on: connection)
            }
        }

        if !linesToParse.isEmpty {
            parseAndEmit(linesToParse, on: connection)
        }
    }

    private func parseAndEmit(_ lines: [String], on connection: NWConnection) {
        parsingQueue.async { [weak self, weak connection] in
            let parsedMessages = lines.map(DXClusterParser.parse)

            Task { @MainActor in
                guard let self, let activeConnection = connection else {
                    return
                }
                guard self.connection === activeConnection, !self.isCancelled else {
                    return
                }

                for message in parsedMessages {
                    self.onEvent?(.message(message))
                }
            }
        }
    }

    private func maybeTriggerLogin(from line: String, on connection: NWConnection) {
        guard !hasSentLogin else {
            return
        }

        // Prompt-driven login path. Timeout fallback still covers silent servers.
        let lowercased = line.lowercased()
        if isLoginPromptLine(lowercased) || isClusterPromptLine(lowercased) {
            sendLoginIfNeeded(on: connection)
        }
    }

    private func sendLoginIfNeeded(on connection: NWConnection) {
        guard !hasSentLogin else {
            return
        }

        // Send callsign once immediately, then rely on retry/fallback timers if needed.
        hasSentLogin = true
        isLoginConfirmed = false
        loginLineBaseline = receivedServerLineCount
        send(callsign, on: connection)

        scheduleLoginRetry(on: connection)
        scheduleStartupFallback(on: connection)
    }

    private func sendStartupCommandsIfNeeded(on connection: NWConnection) {
        guard hasSentLogin, isLoginConfirmed, !hasSentStartupCommands else {
            return
        }

        hasSentStartupCommands = true

        for command in startupCommands(for: clusterFlavor) {
            sendStartupCommand(command, on: connection)
        }
    }

    private func sendStartupCommand(_ command: String, on connection: NWConnection) {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return
        }

        guard sentStartupCommands.insert(normalized).inserted else {
            return
        }

        send(command, on: connection)
    }

    private func scheduleLoginFallback(on connection: NWConnection, delayNanoseconds: UInt64) {
        loginFallbackTask?.cancel()
        loginFallbackTask = Task { [weak self, weak connection] in
            // INTENTIONAL: task cancellation is expected during reconnect/disconnect.
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await MainActor.run {
                guard !Task.isCancelled, let self, let activeConnection = connection else {
                    return
                }
                guard self.connection === activeConnection, !self.isCancelled else {
                    return
                }
                self.sendLoginIfNeeded(on: activeConnection)
            }
        }
    }

    private func scheduleLoginRetry(on connection: NWConnection) {
        loginRetryTask?.cancel()
        loginRetryTask = Task { [weak self, weak connection] in
            // INTENTIONAL: task cancellation is expected during reconnect/disconnect.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                guard !Task.isCancelled, let self, let activeConnection = connection else {
                    return
                }
                guard self.connection === activeConnection, !self.isCancelled else {
                    return
                }
                guard self.hasSentLogin else {
                    return
                }
                guard !self.hasSentStartupCommands else {
                    return
                }
                guard self.receivedServerLineCount == self.loginLineBaseline else {
                    return
                }
                self.send(self.callsign, on: activeConnection)
            }
        }
    }

    private func scheduleStartupFallback(on connection: NWConnection) {
        startupFallbackTask?.cancel()
        startupFallbackTask = Task { [weak self, weak connection] in
            // INTENTIONAL: task cancellation is expected during reconnect/disconnect.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                guard !Task.isCancelled, let self, let activeConnection = connection else {
                    return
                }
                guard self.connection === activeConnection, !self.isCancelled else {
                    return
                }
                self.sendStartupCommandsIfNeeded(on: activeConnection)
            }
        }
    }

    private func startupCommands(for flavor: ClusterFlavor) -> [String] {
        // Commands are aligned with common behavior of major DX cluster families.
        switch flavor {
        case .dxSpider, .ccCluster:
            return ["set/dx", "set/wwv", "set/wcy"]
        case .arCluster:
            return ["set/dx_announcements", "set/wwv_announcements"]
        case .unknown:
            return ["set/dx", "set/dx_announcements", "set/wwv", "set/wwv_announcements", "set/wcy"]
        }
    }

    private func updateClusterFlavor(with line: String) {
        // Lightweight banner/prompt fingerprinting.
        // If no reliable fingerprint is found, connector remains in `.unknown`.
        let lowercased = line.lowercased()

        if lowercased.contains("ar-cluster")
            || lowercased.hasPrefix("arc>")
            || lowercased.contains("ar cluster") {
            clusterFlavor = .arCluster
            return
        }

        if lowercased.contains("cc cluster")
            || lowercased.contains("cluster.gautxori")
            || lowercased.contains("clustercc") {
            clusterFlavor = .ccCluster
            return
        }

        if lowercased.contains("dxspider")
            || lowercased.contains("dx spider")
            || lowercased.hasPrefix("dxspider>") {
            clusterFlavor = .dxSpider
        }
    }

    private func updateLoginState(with line: String) {
        guard hasSentLogin else {
            return
        }

        let lowercased = line.lowercased()

        if isLoginRejectedLine(lowercased) {
            // Server rejected this login attempt; wait for next prompt/fallback cycle.
            hasSentLogin = false
            isLoginConfirmed = false
            return
        }

        if isClusterPromptLine(lowercased)
            || line.hasPrefix("DX de ")
            || line.hasPrefix("WWV")
            || line.hasPrefix("WCY")
            || (lowercased.hasPrefix("to ") && lowercased.contains(" de "))
            || lowercased.contains("logged in")
            || lowercased.contains("welcome") {
            isLoginConfirmed = true
            return
        }

        // Conservative fallback: any non-prompt line after login attempt counts as accepted.
        if receivedServerLineCount > loginLineBaseline && !isLoginPromptLine(lowercased) {
            isLoginConfirmed = true
        }
    }

    private func isLoginPromptLine(_ line: String) -> Bool {
        // Intentional broad matching to support cluster-specific login wording.
        line.contains("enter your call")
            || line.contains("enter callsign")
            || line.contains("enter your callsign")
            || line.hasPrefix("login:")
            || line.contains("callsign:")
            || line.contains("call:")
            || line.contains("call?")
    }

    private func isLoginRejectedLine(_ line: String) -> Bool {
        line.contains("invalid call")
            || line.contains("invalid callsign")
            || line.contains("unknown call")
            || line.contains("bad call")
            || line.contains("access denied")
            || line.contains("login incorrect")
    }

    private func isClusterPromptLine(_ line: String) -> Bool {
        line.hasSuffix(">")
            && (line.contains("dx") || line.contains("arc") || line.contains("cc"))
    }

    private func telnetNegotiationResponse(command: UInt8, option: UInt8) -> [UInt8]? {
        switch command {
        case TelnetByte.do, TelnetByte.dont:
            // Remote asks local side to enable option -> explicitly refuse.
            return [TelnetByte.iac, TelnetByte.wont, option]
        case TelnetByte.will, TelnetByte.wont:
            // Remote announces it will enable option -> request plain mode.
            return [TelnetByte.iac, TelnetByte.dont, option]
        default:
            return nil
        }
    }

    private func resetRuntimeState() {
        cancelRuntimeTasks()
        buffer = ""
        hasSentLogin = false
        isLoginConfirmed = false
        hasSentStartupCommands = false
        receivedServerLineCount = 0
        loginLineBaseline = 0
        clusterFlavor = .unknown
        telnetParserState = .data
        sentStartupCommands.removeAll()
    }

    private func cancelRuntimeTasks() {
        loginFallbackTask?.cancel()
        loginRetryTask?.cancel()
        startupFallbackTask?.cancel()
        loginFallbackTask = nil
        loginRetryTask = nil
        startupFallbackTask = nil
    }
}
