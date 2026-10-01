//
//  PromoImageProcessing.swift
//
//  Copyright 2024-2025 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import UIKit
import CoreImage

/// A collection of convenience functions for managing and processing images
/// to be displayed in various promo content views.
public class PromoImageProcessing {

    /// Decodes an image, optionally resizing it to fit the requested size.
    /// Sourced from http://www.lukeparham.com/blog/2018/3/14/decoding-jpegs-with-the-best
    /// - Parameters:
    ///   - image: The image to decode.
    ///   - fittingSize: Optional size to fit while preserving the image's aspect ratio.
    ///   - scale: The screen scale that the image will be scaled to.
    /// - Returns: The decoded image
    public static func decodedImage(_ image: UIImage?, fittingSize: CGSize? = nil, scale: CGFloat = 1.0) -> UIImage? {
        decodedImage(image, fittingSize: fittingSize, scale: scale, useSystemThumbnailPreparation: true)
    }

    static func decodedImage(_ image: UIImage?,
                             fittingSize: CGSize? = nil,
                             scale: CGFloat = 1.0,
                             useSystemThumbnailPreparation: Bool) -> UIImage? {
        guard let image, let newImage = image.cgImage else { return nil }

        if useSystemThumbnailPreparation, #available(iOS 15.0, *) {
            let size = fittingSize ?? image.size
            let relativeScale = scale / image.scale
            guard let thumbnail = image.preparingThumbnail(of: CGSize(width: size.width * relativeScale,
                                                                      height: size.height * relativeScale)),
                  let cgImage = thumbnail.cgImage else { return nil }
            // Preparation sizes pixels using the source image's scale. Convert
            // that request, then label the result with the desired display scale.
            return UIImage(cgImage: cgImage, scale: scale, orientation: thumbnail.imageOrientation)
        }

        return legacyDecodedImage(newImage, fittingSize: fittingSize, scale: scale)
    }

    /// The pre-iOS 15 decoding path, exposed internally for testing on newer systems.
    static func legacyDecodedImage(_ image: CGImage, fittingSize: CGSize? = nil, scale: CGFloat = 1.0) -> UIImage? {
        let newSize = Self.size(CGSize(width: image.width, height: image.height),
                                fitting: fittingSize)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: Int(newSize.width * scale),
                                height: Int(newSize.height * scale),
                                bitsPerComponent: 8,
                                bytesPerRow: Int(newSize.width * scale) * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.draw(image, in: CGRect(x: 0, y: 0, width: Int(newSize.width * scale), height: Int(newSize.height * scale)))
        if let drawnImage = context?.makeImage() {
            return UIImage(cgImage: drawnImage, scale: scale, orientation: .up)
        }
        return nil
    }

    /// Reuses Core Image resources and render caches across calls.
    private static let sharedContext = CIContext()

    /// Generates a blurred version of the provided image.
    /// - Parameters:
    ///   - image: The image to blur
    ///   - radius: The Gaussian blur radius (default 50)
    ///   - brightness: A brightness adjustment applied after blurring, in the range -1.0 to 1.0 (default -0.05)
    ///   - fittingSize: If provided, the image is resized to fit this size before blurring
    /// - Returns: The blurred image
    public static func blurredImage(_ image: UIImage,
                                    radius: CGFloat = 50.0,
                                    brightness: CGFloat = -0.05,
                                    fittingSize: CGSize? = nil) -> UIImage? {
        guard var ciImage = CIImage(image: image) else { return nil }
        var extent = ciImage.extent
        ciImage = ciImage.clampedToExtent()

        if let fittingSize {
            let scale = min(fittingSize.width / image.size.width,
                            fittingSize.height / image.size.height)
            ciImage = ciImage.samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            extent.size.width *= scale
            extent.size.height *= scale
        }
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let blurImage = blurFilter.outputImage else { return nil }

        guard let brightnessFilter = CIFilter(name: "CIColorControls") else { return nil }
        brightnessFilter.setValue(blurImage, forKey: kCIInputImageKey)
        brightnessFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        guard let brightnessImage = brightnessFilter.outputImage else { return nil }

        // CIContext is thread-safe, so background callers can share its render cache.
        let context = Self.sharedContext
        guard let cgImage = context.createCGImage(brightnessImage, from: extent.integral) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Private

extension PromoImageProcessing {

    /// Fits a size to the requested bounds while preserving its aspect ratio.
    /// - Parameters:
    ///   - size: The source size to be adjusted
    ///   - fittingSize: The bounds that size should be adjusted to fit
    /// - Returns: The adjusted size
    static func size(_ size: CGSize, fitting fittingSize: CGSize?) -> CGSize {
        var newSize = CGSize(width: size.width, height: size.height)
        if let fittingSize {
            let scale = min(fittingSize.width / newSize.width,
                            fittingSize.height / newSize.height)
            newSize.width *= scale
            newSize.height *= scale
        }
        return newSize
    }
}
