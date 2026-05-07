import UIKit

/// Renders a solid-color image of the given size — used by tests that need a real
/// `UIImage` for layout/decoding/blurring without bundling resources.
func makePromoTestImage(size: CGSize, color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}
