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

    /// Takes a `UIImage` instance containing un-decoded image data, and forcefully decodes
    /// that data to a new image copy. Oprtionally, the image can be downscaled at the same time.
    /// Sourced from http://www.lukeparham.com/blog/2018/3/14/decoding-jpegs-with-the-best
    /// - Parameters:
    ///   - image: The un-decoded image.
    ///   - fittingSize: Optionally, a smaller size for the image to be decoded to.
    ///   - scale: The screen scale that the image will be scaled to.
    /// - Returns: The decoded image
    static func decodedImage(_ image: UIImage?, fittingSize: CGSize? = nil, scale: CGFloat = 1.0) -> UIImage? {
        guard let image, let newImage = image.cgImage else { return nil }

        if #available(iOS 15.0, *) {
            let size = fittingSize ?? image.size
            return image.preparingThumbnail(of: CGSize(width: size.width * scale, height: size.height * scale))
        }

        let newSize = Self.size(CGSize(width: newImage.width, height: newImage.height),
                                fitting: fittingSize)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: Int(newSize.width * scale),
                                height: Int(newSize.height * scale),
                                bitsPerComponent: 8,
                                bytesPerRow: Int(newSize.width * scale) * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.draw(newImage, in: CGRect(x: 0, y: 0, width: Int(newSize.width * scale), height: Int(newSize.height * scale)))
        if let drawnImage = context?.makeImage() {
            return UIImage(cgImage: drawnImage, scale: scale, orientation: .up)
        }
        return nil
    }

    /// Generate a blurred version of the provided image
    /// - Parameters:
    ///   - image: The image to blur
    ///   - radius: The amount of blur
    ///   - fittingSize: The size the image is shrunk to
    /// - Returns: The blurred image
    static func blurredImage(_ image: UIImage,
                             radius: CGFloat = 50.0,
                             brightness: CGFloat = -0.05,
                             fittingSize: CGSize? = nil) -> UIImage? {
        guard var ciImage = CIImage(image: image) else { return nil }
        var extent = ciImage.extent
        ciImage = ciImage.clampedToExtent()

        // Scale the image down
        if let fittingSize {
            let scale = min(fittingSize.width / image.size.width,
                            fittingSize.height / image.size.height)
            ciImage = ciImage.samplingNearest()
                .transformed(by: CGAffineTransformMakeScale(scale, scale))
            extent.size.width *= scale
            extent.size.height *= scale
        }
        // Create a blur filter
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let blurImage = blurFilter.outputImage else { return nil }

        // Create brightness filter
        guard let brightnessFilter = CIFilter(name: "CIColorControls") else { return nil }
        brightnessFilter.setValue(blurImage, forKey: kCIInputImageKey)
        brightnessFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        guard let brightnessImage = brightnessFilter.outputImage else { return nil }

        // Perform the generated operations
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(brightnessImage, from: extent.integral) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Private

extension PromoImageProcessing {

    /// Given a size and a fitting size, return what the original size would be
    /// if it was shrunk down/blown up to the fitting size
    /// - Parameters:
    ///   - size: The source size to be adjusted
    ///   - fittingSize: The bounds that size should be adjusted to fit
    /// - Returns: The adjusted size
    fileprivate static func size(_ size: CGSize, fitting fittingSize: CGSize?) -> CGSize {
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
