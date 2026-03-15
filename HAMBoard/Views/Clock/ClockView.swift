//
//  ClockView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 24/11/2025.
//

import SwiftUI

struct ClockView: View {

    @StateObject private var vm = ClockViewModel()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            timeGroup(title: "UTC (Zulu):", value: vm.utcDateTimeText, fontSize: 28)

            timeGroup(title: "Local:", value: vm.localDateTimeText, fontSize: 24)
        }
        .padding(.horizontal, 12)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Subviews

    @ViewBuilder
    private func timeGroup(title: String, value: String, fontSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .foregroundColor(Color("labelColorGreen"))
                .fontWeight(.heavy)

            Text(value)
                .foregroundColor(Color("valueColorGreen"))
        }
        .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}
