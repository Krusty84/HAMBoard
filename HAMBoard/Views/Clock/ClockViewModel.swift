//
//  ClockViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 03/03/2026.
//

import SwiftUI
import Combine

@MainActor
final class ClockViewModel: ObservableObject {

    // MARK: - Properties

    @Published var now: Date = Date()

    private let timerPublisher = Timer.publish(every: 1, on: .main, in: .common)
    private var timerCancellable: AnyCancellable?

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM d [HH:mm]"
        return formatter
    }()

    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEE MMM d [HH:mm]"
        return formatter
    }()

    var utcDateTimeText: String {
        Self.utcFormatter.string(from: now)
    }

    var localDateTimeText: String {
        Self.localFormatter.string(from: now)
    }

    // MARK: - Lifecycle

    init() {
        timerCancellable = timerPublisher
            .autoconnect()
            .sink { [weak self] date in
                self?.now = date
            }
    }

}
