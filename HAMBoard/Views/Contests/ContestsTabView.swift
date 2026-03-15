//
//  ContestsTabView.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 12/03/2026.
//

import SwiftUI

/// Main SwiftUI view displaying ham radio contests calendar
struct ContestsTabView: View {

    @State private var vm = ContestsTabViewModel()
    @FocusState private var focusedContestID: String?

    // MARK: - Body

    var body: some View {
        @Bindable var bindableViewModel = vm

        GeometryReader { proxy in
            let qrPanelWidth = qrPanelWidth(for: proxy.size.width)
            let listPanelWidth = listPanelWidth(
                for: proxy.size.width,
                qrPanelWidth: qrPanelWidth
            )

            HStack(spacing: 200) {
                contestListPane(viewModel: bindableViewModel)
                    .frame(width: listPanelWidth, alignment: .topLeading)

                detailPane(viewModel: bindableViewModel)
                    .frame(width: qrPanelWidth)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .padding(.top, 76)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black.ignoresSafeArea())
            .overlay {
                loadingOverlay()
            }
        }
        .task {
            await bindableViewModel.loadContestsIfNeeded()
            focusedContestID = bindableViewModel.selectedContestID
        }
        .onChange(of: focusedContestID) { _, newFocusedID in
            guard let newFocusedID else {
                return
            }
            bindableViewModel.selectContest(id: newFocusedID)
        }
        .alert("Unable to load contest calendar", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.error?.localizedDescription ?? "Unknown error")
        }
    }

    // MARK: - Subviews

    private func contestListPane(viewModel: ContestsTabViewModel) -> some View {
        VStack(spacing: 0) {
            listHeaderRow

            Rectangle()
                .fill(Color("labelColorGreen").opacity(0.18))
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.contests.enumerated()), id: \.element.id) { index, contest in
                        let isSelected = viewModel.selectedContestID == contest.id
                        let isNextSelected = index + 1 < viewModel.contests.count
                            && viewModel.selectedContestID == viewModel.contests[index + 1].id

                        ContestListRowView(
                            contest: contest,
                            isEvenRow: index.isMultiple(of: 2),
                            isSelected: isSelected
                        )
                        .contentShape(Rectangle())
                        .focusable(true)
                        .focused($focusedContestID, equals: contest.id)
                        .focusEffectDisabled()
                        .onTapGesture {
                            viewModel.selectContest(id: contest.id)
                            focusedContestID = contest.id
                        }

                        if !isSelected && !isNextSelected {
                            Rectangle()
                                .fill(Color("labelColorGreen").opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.94))
        }
        .background(Color.black.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var listHeaderRow: some View {
        HStack(spacing: 100) {
            Text("Name")
                .frame(width: 300, alignment: .leading)

            Text("Date")
                .frame(width: 620, alignment: .leading)
        }
        .font(.headline.weight(.bold))
        .foregroundColor(Color("labelColorGreen"))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.98))
    }

    @ViewBuilder
    private func detailPane(viewModel: ContestsTabViewModel) -> some View {
        VStack {
            ContestLinkQRCodeView(
                linkURL: viewModel.selectedContest?.link,
                regenerationID: viewModel.selectedContest?.id ?? ""
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.black.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func loadingOverlay() -> some View {
        if vm.isLoading && vm.contests.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)

                Text("Waiting for contests data…")
                    .foregroundColor(.white)
                    .font(.title3.monospaced())
            }
            .padding(18)
            .background(Color.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { vm.showError },
            set: { isPresented in
                if !isPresented {
                    vm.error = nil
                }
            }
        )
    }

    private func qrPanelWidth(for totalWidth: CGFloat) -> CGFloat {
        let safeTotalWidth = totalWidth.isFinite ? max(totalWidth, 0) : 0
        return min(max(safeTotalWidth * 0.24, 250), 340)
    }

    private func listPanelWidth(for totalWidth: CGFloat, qrPanelWidth: CGFloat) -> CGFloat {
        let safeTotalWidth = totalWidth.isFinite ? max(totalWidth, 0) : 0
        let safeQRPanelWidth = qrPanelWidth.isFinite ? max(qrPanelWidth, 0) : 0
        let availableWidth = max(safeTotalWidth - safeQRPanelWidth - 12, 0)
        let preferredWidth = max(safeTotalWidth * 0.62, 0)
        return min(preferredWidth, availableWidth)
    }
}

private struct ContestListRowView: View {

    // MARK: - Properties

    let contest: CalendarContestEvent
    let isEvenRow: Bool
    let isSelected: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 100) {
            Text(contest.title)
                .font(.body.weight(.semibold))
                .foregroundColor(Color("valueColorGreen"))
                .frame(width: 300, alignment: .leading)
                .lineLimit(2)

            Text(contest.wrappedDateText)
                .font(.body.monospaced())
                .foregroundColor(Color("valueColorGreen"))
                .frame(width: 620, alignment: .leading)
                .lineLimit(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(rowBackgroundColor)
    }

    // MARK: - Helpers

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color(red: 0.17, green: 0.23, blue: 0.17)
        }
        return isEvenRow ? Color.black.opacity(0.96) : Color.black.opacity(0.84)
    }
}

private struct ContestLinkQRCodeView: View {

    // MARK: - Properties

    @State private var qrContestDetailURLImage: UIImage?

    let linkURL: URL?
    let regenerationID: String

    // MARK: - Body

    var body: some View {
        let size: CGFloat = 320 //Generated QR Code size

        VStack {
                if let qrContestDetailURLImage {
                    Image(uiImage:qrContestDetailURLImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white)
                        )

                    Text("About Contest")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(width: size, alignment: .leading)
                }
             else {
                Color.clear
                    .frame(width: size, height: size)
            }
        }
        .task(id: "\(regenerationID)-\(linkURL?.absoluteString ?? "")") {
            await loadQRCodeIfNeeded()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func loadQRCodeIfNeeded() async {
        guard let linkURL else {
                    qrContestDetailURLImage = nil
            return
        }
        
            qrContestDetailURLImage = await QRCodeGenerator.makeAsync(
            from: linkURL.absoluteString,
            pixelSize: 700
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContestsTabView()
    }
}
