//
//  AboutViewModel.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 26/02/2026.
//

import SwiftUI
import UIKit
import Combine

@MainActor
final class AboutViewModel: ObservableObject {

    // MARK: - Published State

    @Published var qrRepoURLImage: UIImage?
    @Published private(set) var isLoadingQRCode = false

    // MARK: - Constants

    let aboutText: String = "HAMBoard is dedicated to my uncle UA9XG (SK), who gave me my love for amateur radio. \n\nThanks to:\n* Paul L Herrman (N0NBH), Andrew D Rodland (KC2G), and Matthew D Smith (AF7TI) for providing the band propagation data. \n\n* Bruce Horn (WA7BNM) for the contest data. \n\n* Jim Reisert (AD1C) for the country data. \n\n* All DX cluster owners and sysops for their invaluable work in making this possible. \n\n73 all, de UB3ARM"

    // MARK: - Helpers

    func ensureRepoQRCode() {
        guard qrRepoURLImage == nil, !isLoadingQRCode else {
            return
        }
        isLoadingQRCode = true

        Task { [weak self] in
            guard let self else {
                return
            }

            let image = await QRCodeCache.shared.image(for: .repositoryURL)
            self.qrRepoURLImage = image
            self.isLoadingQRCode = false
        }
    }
}
