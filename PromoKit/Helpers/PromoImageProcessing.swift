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

    // http://www.lukeparham.com/blog/2018/3/14/decoding-jpegs-with-the-best
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
                                width: Int(newSize.width),
                                height: Int(newSize.height),
                                bitsPerComponent: 8,
                                bytesPerRow: Int(newSize.width) * 4,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.draw(newImage, in: CGRect(x: 0, y: 0, width: Int(newSize.width), height: Int(newSize.height)))
        if let drawnImage = context?.makeImage() {
            return UIImage(cgImage: drawnImage, scale: scale, orientation: .up)
        }
        return nil
    }
}
