//
//  PromoImageHelpers.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 1/4/2024.
//

import UIKit

/// This file provides a variety of convenience functions for managing and processing images
/// to be displayed in various promo content views

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
        guard let newImage = image?.cgImage else { return nil }

        var newSize = CGSize(width: newImage.width, height: newImage.height)
        if let fittingSize {
            let scale = min(fittingSize.width / newSize.width, 
                            fittingSize.height / newSize.height)
            newSize.width *= scale
            newSize.height *= scale
        }

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
}
