//
//  DXClusterDebugViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 02/03/2026.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class DXClusterDebugViewModel {

    // MARK: - Properties

    var isConnected = false
    var isConnecting = false
    var rawConsoleText = ""
    var error: Error?

    private let maxRawConsoleCharacters = 120_000
    private let trimmedPrefix = "\n...[older raw data trimmed]...\n"

    private var connector: DXClusterTelnetConnector?
    private var activeSessionID = UUID()

    var showError: Bool {
        error != nil
    }

    var isStreaming: Bool {
        isConnected || isConnecting
    }

    // MARK: - Public API

    func setRawDataStreamEnabled(_ isEnabled: Bool, host: String, port: Int, callsign: String) {
        if isEnabled {
            clearLogAndReconnect(host: host, port: port, callsign: callsign)
        } else {
            stopRawStream()
        }
    }

    func clearLogAndReconnect(host: String, port: Int, callsign: String) {
        clearRawConsole()
        startRawStream(host: host, port: port, callsign: callsign)
    }

    func reconnectIfStreaming(host: String, port: Int, callsign: String) {
        guard isStreaming else {
            return
        }
        startRawStream(host: host, port: port, callsign: callsign)
    }

    func stopRawStreamAndClearLog() {
        stopRawStream()
        clearRawConsole()
    }

    func clearError() {
        error = nil
    }

    // MARK: - Helpers

    private func startRawStream(host: String, port: Int, callsign: String) {
        let sessionID = UUID()
        activeSessionID = sessionID
        clearError()
        disconnectConnectionOnly()

        let connector = DXClusterTelnetConnector(host: host, port: port, callsign: callsign)
        connector.onEvent = { [weak self] event in
            self?.handle(event, for: sessionID)
        }
        connector.onRawText = { [weak self] rawText in
            self?.appendRaw(rawText, for: sessionID)
        }
        self.connector = connector
        connector.connect()
    }

    private func stopRawStream() {
        activeSessionID = UUID()
        disconnectConnectionOnly()
        isConnected = false
        isConnecting = false
    }

    private func clearRawConsole() {
        rawConsoleText = ""
    }

    private func disconnectConnectionOnly() {
        connector?.disconnect()
        connector = nil
    }

    private func handle(_ event: DXClusterTelnetConnector.Event, for sessionID: UUID) {
        guard activeSessionID == sessionID else {
            return
        }

        switch event {
        case .connecting:
            isConnecting = true
            isConnected = false
        case .connected:
            isConnecting = false
            isConnected = true
        case .message:
            break
        case .failed(let description):
            isConnecting = false
            isConnected = false
            error = ConnectionError(description: description)
            disconnectConnectionOnly()
        case .disconnectedByRemote:
            isConnecting = false
            isConnected = false
            disconnectConnectionOnly()
        case .disconnected:
            isConnecting = false
            isConnected = false
            disconnectConnectionOnly()
        }
    }

    private func appendRaw(_ rawText: String, for sessionID: UUID) {
        guard activeSessionID == sessionID, !rawText.isEmpty else {
            return
        }

        rawConsoleText += rawText

        if rawConsoleText.count > maxRawConsoleCharacters {
            let overflow = rawConsoleText.count - maxRawConsoleCharacters
            rawConsoleText.removeFirst(min(overflow, rawConsoleText.count))

            if !rawConsoleText.hasPrefix(trimmedPrefix) {
                rawConsoleText = trimmedPrefix + rawConsoleText
            }
        }
    }
}

private struct ConnectionError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}

