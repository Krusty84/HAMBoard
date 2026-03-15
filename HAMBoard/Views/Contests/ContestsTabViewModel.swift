//
//  ContestsTabViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 12/03/2026.
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class ContestsTabViewModel {

    // MARK: - Properties

    var contests: [CalendarContestEvent] = []
    var selectedContestID: String?
    var isLoading = false
    var error: Error?
    var lastUpdatedAt: Date?

    let feedURL: URL
    let session: URLSession

    private var didLoadOnce = false

    private static let defaultFeedURL: URL = {
        guard let url = URL(string: "https://www.contestcalendar.com/calendar.rss") else {
            fatalError("Contest calendar RSS URL must be valid")
        }
        return url
    }()

    var showError: Bool {
        error != nil
    }

    var selectedContest: CalendarContestEvent? {
        guard let selectedContestID else {
            return nil
        }
        
        return contests.first { contest in
            contest.id == selectedContestID
        }
    }

    // MARK: - Lifecycle

    init(
        feedURL: URL = ContestsTabViewModel.defaultFeedURL,
        session: URLSession = .shared
    ) {
        self.feedURL = feedURL
        self.session = session
    }

    // MARK: - Public API

    func loadContestsIfNeeded() async {
        guard !didLoadOnce else {
            return
        }
        await reloadContests()
    }

    func reloadContests() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let (data, response) = try await session.data(from: feedURL)
            try validate(response: response)

            let parsedFeed = try ContestCalendarRSSParser().parse(data: data)
            contests = parsedFeed.items.enumerated().map { index, item in
                let baseID = item.guid.isEmpty ? "\(item.title)-\(index)" : item.guid
                return CalendarContestEvent(
                    id: baseID,
                    title: item.title,
                    dateText: item.descriptionText,
                    link: URL(string: item.linkText)
                )
            }

            if
                let selectedContestID,
                contests.contains(where: { $0.id == selectedContestID })
            {
                self.selectedContestID = selectedContestID
            } else {
                self.selectedContestID = contests.first?.id
            }

            lastUpdatedAt = Date()
            didLoadOnce = true
        } catch {
            self.error = error
        }
    }

    func selectContest(id: String) {
        guard contests.contains(where: { $0.id == id }) else {
            return
        }
        selectedContestID = id
    }

    // MARK: - Helpers

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarFeedError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw CalendarFeedError.badStatusCode(httpResponse.statusCode)
        }
    }
}

struct CalendarContestEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let dateText: String
    let link: URL?

    var wrappedDateText: String {
        ContestDateTextFormatter.format(dateText)
    }
}

private enum ContestDateTextFormatter {
    static func format(_ rawValue: String, maxLineLength: Int = 44) -> String {
        let normalized = normalizeWhitespace(rawValue)
        guard !normalized.isEmpty else {
            return rawValue
        }

        let segments = splitTopLevel(normalized, by: " and ")
        if segments.count <= 1 {
            return wrapWords(normalized, maxLineLength: maxLineLength)
        }

        return segments
            .map { wrapWords($0, maxLineLength: maxLineLength) }
            .joined(separator: "\n")
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitTopLevel(_ value: String, by delimiter: String) -> [String] {
        guard !value.isEmpty else {
            return []
        }

        var parts: [String] = []
        var currentPart = ""
        var depth = 0
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]

            if character == "(" {
                depth += 1
                currentPart.append(character)
                index = value.index(after: index)
                continue
            }

            if character == ")" {
                depth = max(0, depth - 1)
                currentPart.append(character)
                index = value.index(after: index)
                continue
            }

            if depth == 0, value[index...].hasPrefix(delimiter) {
                parts.append(currentPart.trimmingCharacters(in: .whitespacesAndNewlines))
                currentPart = ""
                index = value.index(index, offsetBy: delimiter.count)
                continue
            }

            currentPart.append(character)
            index = value.index(after: index)
        }

        let trimmedPart = currentPart.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPart.isEmpty {
            parts.append(trimmedPart)
        }

        return parts.isEmpty ? [value] : parts
    }

    private static func wrapWords(_ value: String, maxLineLength: Int) -> String {
        let words = value.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return value
        }

        var lines: [String] = []
        var currentLine = ""

        for word in words {
            let token = String(word)

            if currentLine.isEmpty {
                currentLine = token
                continue
            }

            if currentLine.count + 1 + token.count <= maxLineLength {
                currentLine += " " + token
            } else {
                lines.append(currentLine)
                currentLine = token
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.joined(separator: "\n")
    }
}

private enum CalendarFeedError: LocalizedError {
    case invalidResponse
    case badStatusCode(Int)
    case invalidXML
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response received from contest calendar."
        case .badStatusCode(let statusCode):
            return "Contest calendar request failed with HTTP \(statusCode)."
        case .invalidXML:
            return "Contest calendar RSS data could not be parsed."
        }
    }
}

private struct RSSFeedItem {
    var title: String = ""
    var linkText: String = ""
    var descriptionText: String = ""
    var guid: String = ""
}

private struct ContestCalendarRSS {
    let items: [RSSFeedItem]
}

private final class ContestCalendarRSSParser: NSObject, XMLParserDelegate {
    
    private var items: [RSSFeedItem] = []
    private var currentItem = RSSFeedItem()
    private var isInsideItem = false
    private var currentValue = ""
    
    func parse(data: Data) throws -> ContestCalendarRSS {
        items = []
        currentItem = RSSFeedItem()
        isInsideItem = false
        currentValue = ""
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            throw parser.parserError ?? CalendarFeedError.invalidXML
        }
        
        return ContestCalendarRSS(items: items)
    }
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        currentValue = ""
        
        if elementName == "item" {
            isInsideItem = true
            currentItem = RSSFeedItem()
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue.append(string)
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if isInsideItem {
            switch elementName {
            case "title":
                currentItem.title = trimmedValue
            case "link":
                currentItem.linkText = trimmedValue
            case "description":
                currentItem.descriptionText = trimmedValue
            case "guid":
                currentItem.guid = trimmedValue
            case "item":
                items.append(currentItem)
                isInsideItem = false
            default:
                break
            }
        }
        
        currentValue = ""
    }
}
