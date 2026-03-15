//
//  QRCodeCache.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 03/03/2026.
//

import SwiftUI
import UIKit

@MainActor
final class QRCodeCache {

    static let shared = QRCodeCache()

    // MARK: - Properties

    private var cachedImages: [QRCodeAsset: UIImage] = [:]
    private var preloadTask: Task<Void, Never>?

    // MARK: - Public API

    func preloadOnFirstLoad() {
        if preloadTask != nil {
            return
        }

        preloadTask = Task(priority: .background) {
            async let dxClusterImage = QRCodeGenerator.makeAsync(
                from: QRCodeAsset.dxClusterURL.source,
                pixelSize: QRCodeAsset.dxClusterURL.pixelSize
            )
            async let repositoryImage = QRCodeGenerator.makeAsync(
                from: QRCodeAsset.repositoryURL.source,
                pixelSize: QRCodeAsset.repositoryURL.pixelSize
            )

            let dxImage = await dxClusterImage
            let repoImage = await repositoryImage

            if let dxImage {
                cachedImages[.dxClusterURL] = dxImage
            }
            if let repoImage {
                cachedImages[.repositoryURL] = repoImage
            }
        }
    }

    func image(for asset: QRCodeAsset) async -> UIImage? {
        if let image = cachedImages[asset] {
            return image
        }

        if let preloadTask {
            await preloadTask.value
            if let image = cachedImages[asset] {
                return image
            }
        }

        let image = await QRCodeGenerator.makeAsync(from: asset.source, pixelSize: asset.pixelSize)
        if let image {
            cachedImages[asset] = image
        }
        return image
    }
}

enum QRCodeAsset: CaseIterable {
    case dxClusterURL
    case repositoryURL

    var source: String {
        switch self {
        case .dxClusterURL:
            return "https://www.dxcluster.info/telnet/index.php"
        case .repositoryURL:
            return "https://github.com/Krusty84/HAMBoard"
        }
    }

    var pixelSize: CGFloat {
        800
    }
}
