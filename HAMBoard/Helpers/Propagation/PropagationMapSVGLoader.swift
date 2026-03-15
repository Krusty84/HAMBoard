//
//  SVGViewer.swift
//  HAMBoard
//
//  Created by Sedoykin Alexey on 20/11/2025.
//

import SwiftUI
import SVGKit

struct PropagationMapSVGLoader: UIViewRepresentable {

    let url: URL

    // A container that holds the SVG view and a centered SwiftUI ProgressView overlay.
    final class ContainerView: UIView {
        let imageView: SVGKFastImageView
        private let progressView: UIView
        private let progressHost: UIHostingController<AnyView>

        init(imageView: SVGKFastImageView) {
            self.imageView = imageView

            // SwiftUI ProgressView hosted inside UIKit
            let progressHost = UIHostingController(
                rootView: AnyView(
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.4)
                        
                        Text("Waiting for propagation data…")
                            .foregroundColor(.white)
                            .font(.title3.monospaced())
                    }
                    
                    
                )
            )
            progressHost.loadViewIfNeeded()

            self.progressHost = progressHost
            self.progressView = progressHost.view ?? UIView(frame: .zero)

            super.init(frame: .zero)

            backgroundColor = .black

            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)

            // Add hosted SwiftUI view
            progressView.translatesAutoresizingMaskIntoConstraints = false
            progressView.backgroundColor = .clear
            progressView.isUserInteractionEnabled = false // avoid focus / touches
            addSubview(progressView)

            NSLayoutConstraint.activate([
                // Pin image view to all edges
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

                // Center ProgressView
                progressView.centerXAnchor.constraint(equalTo: centerXAnchor),
                progressView.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])

            setLoading(false)
        }

        func setLoading(_ isLoading: Bool) {
            progressView.isHidden = !isLoading
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    func makeUIView(context: Context) -> ContainerView {
        // Create a minimal placeholder SVG image from data.
        let tinySVG = """
        <svg xmlns="http://www.w3.org/2000/svg" width="1" height="1" viewBox="0 0 1 1">
            <rect width="1" height="1" fill="none"/>
        </svg>
        """
        let placeholderData = Data(tinySVG.utf8)
        let placeholderImage = SVGKImage(data: placeholderData) ?? SVGKImage()

        let imageView: SVGKFastImageView
        if let fastImageView = SVGKFastImageView(svgkImage: placeholderImage) {
            imageView = fastImageView
        } else {
            let fallbackImageView = SVGKFastImageView(frame: .zero)
            fallbackImageView.image = placeholderImage
            imageView = fallbackImageView
        }
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black

        let container = ContainerView(imageView: imageView)

        context.coordinator.loadSVG(in: container, from: url)

        return container
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        // If URL can change, you can reload here:
        // context.coordinator.loadSVG(in: uiView, from: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {

        private var currentTask: URLSessionDataTask?

        func loadSVG(in container: ContainerView, from url: URL) {
            currentTask?.cancel()

            DispatchQueue.main.async {
                container.setLoading(true)
            }

            let request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 15
            )

            currentTask = URLSession.shared.dataTask(with: request) { [weak container] data, _, error in
                guard let container = container else { return }

                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    DispatchQueue.main.async { container.setLoading(false) }
                    return
                }

                guard let data, error == nil else {
                    DispatchQueue.main.async { container.setLoading(false) }
                    return
                }

                let svgImage = SVGKImage(data: data)

                DispatchQueue.main.async {
                    if container.imageView.bounds.size == .zero {
                        svgImage?.size = CGSize(width: 1920, height: 1080)
                    } else {
                        svgImage?.size = container.imageView.bounds.size
                    }

                    container.imageView.image = svgImage
                    container.imageView.setNeedsLayout()
                    container.setLoading(false)
                }
            }

            currentTask?.resume()
        }
    }
}
