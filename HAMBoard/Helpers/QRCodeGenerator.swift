//
//  QRCodeGenerator.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 26/02/2026.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeGenerator {

    // MARK: - Public API

    static func makeAsync(from string: String, pixelSize: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = make(from: string, pixelSize: pixelSize)
                continuation.resume(returning: image)
            }
        }
    }

    static func make(from string: String, pixelSize: CGFloat) -> UIImage? {
        let data = Data(string.utf8)

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else {
            return nil
        }

        let extent = ciImage.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let scale = min(pixelSize / extent.width, pixelSize / extent.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
