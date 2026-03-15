//
//  PropagationTabViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 19/11/2025.
//

import Foundation
import SwiftUI
import Combine

enum PropagationPage: Int, CaseIterable, Identifiable {
    case general
    case muf
    case fof2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .muf:
            return "MUF"
        case .fof2:
            return "foF2"
        }
    }

    var mapURL: URL? {
        switch self {
        case .general:
            return nil
        case .muf:
            return URL(string: "https://prop.kc2g.com/renders/current/mufd-normal-now.svg")
        case .fof2:
            return URL(string: "https://prop.kc2g.com/renders/current/fof2-normal-now.svg")
        }
    }
}

@MainActor
final class PropagationTabViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedPage: PropagationPage = .general

    // MARK: - Constants

    let pages: [PropagationPage] = PropagationPage.allCases
}
