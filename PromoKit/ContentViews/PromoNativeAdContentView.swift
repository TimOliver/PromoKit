//
//  PromoNativeAdContentView.swift
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

import Foundation
#if PROMOKIT_GOOGLE_ADS
import PromoKit
#endif
import GoogleMobileAds

/// A content view that can display a complete native Google AdMob view.
/// The ad is sized to fit the current bounds, and is completely rendered with native UI elements.
final public class PromoNativeAdContentView: PromoContentView {

    /// The ad model object that is being displayed
    public var nativeAd: NativeAd? {
        didSet { adView.configureContentViews(with: nativeAd) }
    }

    /// A blurred image of the video thumbnail to be used as a backdrop
    /// against the video
    public var mediaBackgroundImage: UIImage? {
        set { adView.mediaBackgroundImage = newValue }
        get { adView.mediaBackgroundImage }
    }

    /// Fetch the frame for the Ad Choices view (The small info button in the top corner)
    public var adChoicesViewFrame: CGRect {
        // Find the object named GADNativeAdAttributionView and return its frame if found
        adView.subviews.first(where: {
            NSStringFromClass(type(of: $0)).contains("GADNativeAdAttributionView")
        })?.frame ?? .zero
    }

    /// The widest the ad's card may be laid out, independent of the space offered.
    /// Forwarded from the provider; see `PromoNativeAdProvider.maximumContentWidth`.
    public var maximumContentWidth: CGFloat {
        set { adView.maximumWidth = newValue }
        get { adView.maximumWidth }
    }

    /// The tallest the ad's card may be laid out, independent of the space offered.
    /// Forwarded from the provider; see `PromoNativeAdProvider.maximumContentHeight`.
    public var maximumContentHeight: CGFloat {
        set { adView.maximumHeight = newValue }
        get { adView.maximumHeight }
    }

    // The hosted native ad view
    private let adView = PromoNativeAdView()

    public required init(promoView: PromoView) {
        super.init(promoView: promoView)
        addSubview(adView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var wantsSizingControl: Bool { true }

    public override func layoutSubviews() {
        super.layoutSubviews()
        adView.frame = bounds

        adView.backgroundColor = promoView?.backgroundView.backgroundColor
        adView.headlineView?.backgroundColor = adView.backgroundColor
        adView.bodyView?.backgroundColor = adView.backgroundColor
    }

    public override func prepareForReuse() {
        self.nativeAd = nil
        adView.reset()
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        adView.sizeThatFits(size)
    }
}

// MARK: - PromoNativeAdView

/// The inner ad view view that is managed by `PromoNativeAdContentView`.
/// It is a subclass of `GADNativeAdView` and manages all of the UI configuration
/// and events between PromoKit and Google AdMob.
final public class PromoNativeAdView: NativeAdView {

    // A generated blurred image placed behind the ad when the aspect ratio
    // doesn't align
    public var mediaBackgroundImage: UIImage? {
        set { contentMediaContainerView.image = newValue }
        get { contentMediaContainerView.image }
    }

    // Main, bold headline title shown at the top
    private let headlineLabel = UILabel()

    // Any auxiliary body text
    private let bodyLabel = UILabel()

    // An ad badge label
    private let adLabel = UILabel()

    // A large call-to-action button shown at the bottom
    private let actionButton = PromoNativeAdActionButton()

    // An icon image view optionally shown next to the headline
    private let iconImageView = UIImageView()

    // A container view hosting the media view
    private let contentMediaContainerView = UIImageView()

    // If media, the content view used to show the media
    private let contentMediaView = MediaView()

    // For easier testing, remove the 'Test mode' string from the title
    private func headlineText(for nativeAd: NativeAd?) -> String {
#if DEBUG
        nativeAd?.headline?.replacingOccurrences(of: "Test mode: ", with: "") ?? ""
#else
        nativeAd?.headline ?? ""
#endif
    }

    // If a body string was supplied, show that. If not, show the name of the store,
    // and the price as a string instead
    private func bodyText(for nativeAd: NativeAd?) -> String? {
        if let body = nativeAd?.body {
            return body
        } else if let store = nativeAd?.store {
            let price = nativeAd?.price ?? ""
            return "\(store)" + (!price.isEmpty ? " • \(price)" : "")
        }
        return nil
    }

    public init() {
        super.init(frame: .zero)
        configureContentViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func reset() {
        self.nativeAd = nil
        // Detach the views from the Google references until the next layout pass
        self.headlineView = nil
        self.bodyView = nil
        self.iconView = nil
        self.mediaView = nil
        self.callToActionView = nil

        headlineLabel.attributedText = nil
        headlineLabel.text = nil
        bodyLabel.attributedText = nil
        bodyLabel.text = nil
        actionButton.title = nil
        iconImageView.image = nil
        contentMediaView.mediaContent = nil
        mediaBackgroundImage = nil
    }

    private func configureContentViews() {
        let headlineFont = UIFont.systemFont(ofSize: 21, weight: .bold)
        headlineLabel.font = UIFontMetrics.default.scaledFont(for: headlineFont)
        headlineLabel.numberOfLines = 2
        addSubview(headlineLabel)

        adLabel.text = "Ad"
        if #available(iOS 13.0, *) {
            adLabel.backgroundColor = .label
            adLabel.layer.cornerCurve = .continuous
        } else {
            adLabel.backgroundColor = .black
        }
        adLabel.textAlignment = .center
        adLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        adLabel.layer.cornerRadius = 6
        adLabel.clipsToBounds = true
        addSubview(adLabel)

        let bodyFont = UIFont.systemFont(ofSize: 16.0)
        bodyLabel.font = UIFontMetrics.default.scaledFont(for: bodyFont)
        bodyLabel.numberOfLines = 3
        if #available(iOS 13.0, *) {
            bodyLabel.textColor = .secondaryLabel
        }
        addSubview(bodyLabel)

        iconImageView.clipsToBounds = true
        if #available(iOS 13.0, *) {
            iconImageView.layer.cornerCurve = .continuous
        }
        addSubview(iconImageView)

        contentMediaContainerView.isUserInteractionEnabled = true
        contentMediaContainerView.backgroundColor = UIColor(white: 1.0, alpha: 0.5)
        contentMediaContainerView.clipsToBounds = true
        contentMediaContainerView.contentMode = .scaleAspectFill
        if #available(iOS 13.0, *) {
            contentMediaContainerView.layer.cornerCurve = .continuous
        }
        addSubview(contentMediaContainerView)

        contentMediaView.isUserInteractionEnabled = true
        contentMediaView.frame.size = CGSize(width: 120, height: 120)
        contentMediaContainerView.addSubview(contentMediaView)

    }

    public func configureContentViews(with nativeAd: NativeAd?) {
        guard let nativeAd else {
            reset()
            return
        }

        iconImageView.image = nativeAd.icon?.image

        if let body = bodyText(for: nativeAd) {
            bodyLabel.attributedText = NSAttributedString(string: body)
        }

        contentMediaContainerView.image = mediaBackgroundImage
        contentMediaView.mediaContent = nativeAd.mediaContent

        actionButton.title = nil
        if let cta = nativeAd.callToAction {
            actionButton.title = cta.capitalized
        }

        // Force a layout to ensure the elements are appropriately sized
        frame.size = sizeThatFits(CGSize(width: 1000, height: 1000), nativeAd: nativeAd)
        layoutSubviews(for: nativeAd)

        // Set the ad after everything else is set
        self.nativeAd = nativeAd
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutSubviews(for: self.nativeAd)
    }

    public func layoutSubviews(for nativeAd: NativeAd?) {
        super.layoutSubviews()

        // Skip layout if we don't have an ad yet
        guard let nativeAd else { return }

        let size = frame.insetBy(dx: padding, dy: padding).size
        let aspectRatio = nativeAd.mediaContent.aspectRatio

        // Set the creative beside its text whenever the box leaves room for both.
        switch Self.layoutFormat(containerSize: size,
                                 mediaAspectRatio: aspectRatio,
                                 minimumTextColumnWidth: minimumTextColumnWidth,
                                 maximumMediaWidthFraction: maximumMediaWidthFraction) {
        case .sideBySide:
            layoutSubviewsInLandscapeFormat(size: size, nativeAd: nativeAd)
        case .stacked:
            layoutSubviewsInPortraitFormat(size: size, nativeAd: nativeAd)
        }

        // Once all the views are configured, connect them to Google's references.
        // We defer them this late since it seems Google's validator occurs when they are
        // connected, so they must be in their final resting position by then
        self.headlineView = headlineLabel
        self.bodyView = !bodyLabel.isHidden ? bodyLabel : nil
        self.iconView = !iconImageView.isHidden ? iconImageView : nil
        self.mediaView = contentMediaView
        self.callToActionView = actionButton
    }

    private func layoutSubviewsInLandscapeFormat(size: CGSize, nativeAd: NativeAd) {
        // Lay out the ad view on the right hand side
        let aspectRatio = nativeAd.mediaContent.aspectRatio
        // The creative takes the full height until that would claim more than
        // `maximumMediaWidthFraction` of the card. Past that it yields — shrinking
        // and picking up vertical letterboxing — so the text column keeps its width
        // and the text never has to scale down to fit beside it.
        let mediaBox = CGSize(width: size.width, height: size.height - (padding * 2.0))
        let media = Self.mediaSize(fitting: mediaBox,
                                   aspectRatio: aspectRatio,
                                   maximumWidthFraction: maximumMediaWidthFraction)
        let mediaWidth = media.width
        let mediaHeight = media.height
        contentMediaContainerView.frame.size = CGSize(width: mediaWidth, height: mediaHeight)
        contentMediaContainerView.frame.origin = CGPoint(x: (size.width - (googleButtonWidth + padding)) - mediaWidth,
                                                         y: padding + ((mediaBox.height - mediaHeight) * 0.5))
        contentMediaView.frame = contentMediaContainerView.bounds
        contentMediaContainerView.layer.cornerRadius = 15.0

        // With the media view laid out, work out the remaning space we have
        let mediaTotalWidth = (mediaWidth + googleButtonWidth + padding + innerMargin)
        let textContentSize = CGSize(width: size.width - mediaTotalWidth,
                                     height: size.height)

        // Layout the icon if it is available
        iconImageView.isHidden = iconImageView.image == nil
        if !iconImageView.isHidden, let icon = nativeAd.icon?.image {
            if iconImageView.superview == nil { addSubview(iconImageView) }
            let aspectRatio = icon.size.width / icon.size.height
            let iconSize = CGSize(width: iconHeight * aspectRatio, height: iconHeight)
            let iconOrigin = CGPoint(x: (textContentSize.width - iconSize.width) * 0.5,
                                     y: textContentSize.height * 0.12)
            iconImageView.frame = pixelAligned(CGRect(origin: iconOrigin, size: iconSize))
            iconImageView.layer.cornerRadius = iconSize.height * 0.23
        } else {
            iconImageView.removeFromSuperview()
        }

        // Layout the action button at the bottom
        if !(actionButton.title?.isEmpty ?? true) {
            actionButton.tintColor = self.tintColor
            let buttonSize = CGSize(width: textContentSize.width, height: ctaButtonHeight)
            let buttonOrigin = CGPoint(x: padding, y: size.height - (ctaButtonHeight + padding))
            actionButton.frame = CGRect(origin: buttonOrigin, size: buttonSize)
            if actionButton.superview == nil { insertSubview(actionButton, at: 0) }
        } else {
            actionButton.isHidden = true
            actionButton.removeFromSuperview()
        }

        // Fill the remaining space with the text labels
        let iconOriginY = iconImageView.isHidden ? padding : iconImageView.frame.maxY + titleVerticalSpacing
        let ctaOriginY = actionButton.isHidden ? (size.height - padding) : actionButton.frame.minY - innerMargin
        let remainingTextSize = CGSize(width: textContentSize.width,
                                       height: ctaOriginY - iconOriginY)

        // Lay out the title
        let headlineStyle = NSMutableParagraphStyle()
        headlineStyle.firstLineHeadIndent = 0
        headlineLabel.attributedText = NSAttributedString(string: headlineText(for: nativeAd),
                                                          attributes: [.paragraphStyle: headlineStyle ])
        headlineLabel.textAlignment = .center
        headlineLabel.frame.size = headlineLabel.sizeThatFits(remainingTextSize)
        headlineLabel.frame.origin = CGPoint(x: (remainingTextSize.width - headlineLabel.frame.width) * 0.5,
                                             y: iconImageView.isHidden ? remainingTextSize.height * 0.2 : iconOriginY)

        // Lay out the ad label
        adLabel.frame.size = adLabelSize
        adLabel.frame.origin = CGPoint(x: 7, y: 3)
        adLabel.textColor = backgroundColor

        // We're done if the label is hidden
        bodyLabel.text = bodyText(for: nativeAd)
        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true
        if bodyLabel.isHidden { return }

        // Lay out the subtitle
        bodyLabel.textAlignment = .center
        bodyLabel.frame.size = bodyLabel.sizeThatFits(remainingTextSize)
        bodyLabel.frame.origin = CGPoint(x: (remainingTextSize.width - bodyLabel.frame.width) * 0.5,
                                         y: headlineLabel.frame.maxY + titleVerticalSpacing)

        // Scale the labels down if they overflowed
        let totalHeight = bodyLabel.frame.height + titleVerticalSpacing + headlineLabel.frame.height
        if totalHeight < remainingTextSize.height {
            return
        }

        let scale = remainingTextSize.height / (totalHeight - titleVerticalSpacing)
        headlineLabel.frame.size.height *= scale
        bodyLabel.frame.size.height *= scale
        bodyLabel.frame.origin.y = headlineLabel.frame.maxY + titleVerticalSpacing
    }

    private func layoutSubviewsInPortraitFormat(size: CGSize, nativeAd: NativeAd) {
        var origin = CGPoint(x: padding, y: padding)

        // Lay out the icon view
        var iconSize = CGSize.zero
        iconImageView.isHidden = iconImageView.image == nil
        if !iconImageView.isHidden, let icon = nativeAd.icon?.image {
            if iconImageView.superview == nil { addSubview(iconImageView) }
            let aspectRatio = icon.size.width / icon.size.height
            iconSize = CGSize(width: iconHeight * aspectRatio, height: iconHeight)
            iconImageView.frame = pixelAligned(CGRect(origin: origin, size: iconSize))
            iconImageView.layer.cornerRadius = iconSize.height * 0.23
        } else {
            iconImageView.removeFromSuperview()
        }

        // Hide the body if we don't have any text
        bodyLabel.text = bodyText(for: nativeAd)
        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true

        // Position the title text
        let textX = iconImageView.isHidden ? padding : iconSize.width + innerMargin
        let textWidth = size.width - (textX + googleButtonWidth + (padding * 2.0) + (needsCompactLayout ? compactActionSize.width : 0.0))
        let textFittingSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

        let headlineStyle = NSMutableParagraphStyle()
        headlineStyle.firstLineHeadIndent = headlineIndent
        headlineLabel.attributedText = NSAttributedString(string: headlineText(for: nativeAd),
                                                          attributes: [.paragraphStyle: headlineStyle ])

        headlineLabel.textAlignment = .left
        headlineLabel.frame.size = headlineLabel.sizeThatFits(textFittingSize)
        bodyLabel.frame.size = bodyLabel.isHidden ? .zero : bodyLabel.sizeThatFits(textFittingSize)
        let totalTextHeight = headlineLabel.frame.height + titleVerticalSpacing + bodyLabel.frame.height

        let textY = totalTextHeight < iconSize.height ? (iconSize.height - totalTextHeight) / 2.0 : padding
        headlineLabel.frame.origin = CGPoint(x: textX, y: textY)

        // Lay out the ad label at the start of the title label
        adLabel.frame.size = adLabelSize
        adLabel.frame.origin = CGPoint(x: headlineLabel.frame.minX,
                                       y: headlineLabel.frame.minY + adLabelOffset)
        adLabel.textColor = backgroundColor

        // Position the body text
        if !bodyLabel.isHidden {
            if bodyLabel.superview == nil { addSubview(bodyLabel) }
            let textY = headlineLabel.frame.maxY + titleVerticalSpacing
            bodyLabel.frame.origin = CGPoint(x: textX, y: textY)
            bodyLabel.textAlignment = .left
        } else {
            bodyLabel.removeFromSuperview()
        }

        origin.y = max(iconImageView.frame.maxY, max(headlineLabel.frame.maxY, bodyLabel.frame.maxY)) + innerMargin

        if !(actionButton.title?.isEmpty ?? true) {
            if actionButton.superview == nil { insertSubview(actionButton, at: 0) }
            actionButton.tintColor = self.tintColor
            if !needsCompactLayout {
                let buttonSize = CGSize(width: size.width, height: ctaButtonHeight)
                let buttonOrigin = CGPoint(x: padding, y: size.height - ctaButtonHeight)
                actionButton.frame = pixelAligned(CGRect(origin: buttonOrigin, size: buttonSize))
            } else {
                actionButton.frame.size = compactActionSize
                actionButton.frame.origin = CGPoint(x: size.width - (actionButton.frame.width + padding),
                                                    y: max(headlineLabel.frame.minY + ((totalTextHeight - compactActionSize.height) / 2.0),
                                                           padding + googleButtonWidth + titleVerticalSpacing))
            }
            actionButton.setNeedsLayout()
        } else {
            actionButton.removeFromSuperview()
        }

        // Position the media container
        let mediaContent = nativeAd.mediaContent
        let aspectRatio = mediaContent.aspectRatio > 0.0 ? mediaContent.aspectRatio : 1.0
        let actionButtonY = (actionButton.superview != nil && !needsCompactLayout) ? (actionButton.frame.minY - innerMargin) : size.height
        let mediaContainerSize = CGSize(width: size.width, height: actionButtonY - origin.y)
        contentMediaContainerView.frame = pixelAligned(CGRect(origin: CGPoint(x: padding, y: origin.y),
                                                              size: mediaContainerSize))
        contentMediaContainerView.layer.cornerRadius = 15.0
        updateMediaViewBackgroundColor()

        // Fit the media inside the container, keeping the creative's shape.
        // Centring halves an odd remainder, so an un-snapped media view lands on a
        // half-pixel and the container's tint bleeds through as a hairline sliver
        // down one edge. Snap by edges so a media view that should span the
        // container's full width reaches both sides exactly.
        let fittedSize = Self.fittedMediaSize(containerSize: mediaContainerSize, aspectRatio: aspectRatio)
        contentMediaView.frame = pixelAligned(CGRect(x: (mediaContainerSize.width - fittedSize.width) * 0.5,
                                                     y: (mediaContainerSize.height - fittedSize.height) * 0.5,
                                                     width: fittedSize.width,
                                                     height: fittedSize.height))

    }

    private func updateMediaViewBackgroundColor() {
        var h: CGFloat = 0, s: CGFloat = 0
        var b: CGFloat = 0, a: CGFloat = 0

        var color: UIColor? = backgroundColor
        if #available(iOS 13.0, *) {
            color = backgroundColor?.resolvedColor(with: traitCollection)
        }

        guard let color, color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return }

        contentMediaContainerView.backgroundColor = UIColor(hue: h,
                                                   saturation: max(s - 0.1, 0.0),
                                                   brightness: min(b + 0.05, 1.0),
                                                   alpha: a)
    }

    // MARK: - Sizing

    // Static sizing values
    private var needsCompactLayout: Bool { traitCollection.verticalSizeClass == .compact }
    var maximumWidth: CGFloat = PromoNativeAdProvider.defaultMaximumContentWidth
    private var minimumWidth: CGFloat { 340 }
    var maximumHeight: CGFloat = PromoNativeAdProvider.defaultMaximumContentHeight
    private var headlineIndent: CGFloat { 31 }
    private var adLabelOffset: CGFloat { 4 }
    private var adLabelSize: CGSize { CGSize(width: 26, height: 18) }
    private var padding: CGFloat { 1.0 }
    private var outerMargin: CGFloat { frame.width < 375 ? 8.0 : 16.0 }
    private var innerMargin: CGFloat { 12.0 }
    private var titleVerticalSpacing: CGFloat { 1.0 }
    private var ctaButtonHeight: CGFloat { 54 }
    private var googleButtonWidth: CGFloat { 20.0 }
    private var displayScale: CGFloat { max(2.0, traitCollection.displayScale) }

    /// Snaps a value to the device's physical pixel grid.
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * displayScale).rounded() / displayScale
    }

    /// Snaps a rect to the pixel grid by its EDGES rather than its origin and size.
    ///
    /// Rounding origin and size separately is what produces hairline seams: each is
    /// rounded independently, so the resulting trailing edge can land up to a whole
    /// pixel away from where it should, and whatever sits behind shows through the
    /// gap. Rounding the edges keeps a view that should meet its container's edge
    /// actually meeting it.
    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let minX = pixelAligned(rect.minX), minY = pixelAligned(rect.minY)
        let maxX = pixelAligned(rect.maxX), maxY = pixelAligned(rect.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    private var iconHeight: CGFloat { 64.0 }
    private var compactActionSize: CGSize { CGSize(width: 120, height: 40) }

    /// The narrowest column of text worth setting beside a creative. Below this the
    /// headline wraps to a word or two a line, and stacking reads better.
    private var minimumTextColumnWidth: CGFloat { 240.0 }

    /// The most of the card's width a creative may claim when set beside its text.
    private var maximumMediaWidthFraction: CGFloat { 0.55 }

    /// Given an outer size, work out the most appropriate size this view should be
    /// - Parameter size: Size constraining the ad view
    /// - Returns: Resulting size of the ad view
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        sizeThatFits(size, nativeAd: self.nativeAd)
    }

    private func sizeThatFits(_ size: CGSize, nativeAd: NativeAd?) -> CGSize {
        guard let nativeAd else { return .zero }

        // Aspect ratio of the ad view
        let aspectRatio = nativeAd.mediaContent.aspectRatio

        // Must reach the same verdict as -layoutSubviews(for:), or the card is
        // measured for one arrangement and then drawn as the other.
        let contentBox = CGSize(width: size.width - (padding * 2.0),
                                height: size.height - (padding * 2.0))
        let isHorizontalLayout = Self.layoutFormat(containerSize: contentBox,
                                                   mediaAspectRatio: aspectRatio,
                                                   minimumTextColumnWidth: minimumTextColumnWidth,
                                                   maximumMediaWidthFraction: maximumMediaWidthFraction) == .sideBySide
        if isHorizontalLayout {
            let height = size.height
            let mediaWidth = (height * aspectRatio) + innerMargin
            let adjustedWidth = min(size.width, mediaWidth + 375)
            return CGSize(width: adjustedWidth, height: height)
        }

        // Line out the elements vertically
        var iconSize = CGSize.zero
        if let icon = nativeAd.icon?.image {
            let iconAspectRatio = icon.size.width / icon.size.height
            iconSize = CGSize(width: iconHeight * iconAspectRatio, height: iconHeight)
        }

        headlineLabel.text = headlineText(for: nativeAd)
        let body = bodyText(for: nativeAd)
        if let body {
            bodyLabel.numberOfLines = needsCompactLayout ? 2 : 3
            bodyLabel.text = body
        }

        // Everything the card owes before the media band is given any height at all.
        func chromeHeight(forWidth cardWidth: CGFloat) -> CGFloat {
            var textWidth = cardWidth - ((iconSize.width > 0.0 ? innerMargin + iconSize.width : 0.0) + googleButtonWidth)
            if needsCompactLayout { textWidth -= (innerMargin + compactActionSize.width) }
            let textSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

            var textHeight = headlineLabel.sizeThatFits(textSize).height
            if body != nil {
                textHeight += titleVerticalSpacing + bodyLabel.sizeThatFits(textSize).height
            }

            var chrome = (padding * 2.0) + max(textHeight, iconSize.height) + innerMargin
            if !needsCompactLayout { chrome += innerMargin + ctaButtonHeight }
            return chrome
        }

        let availableSize = CGSize(width: min(size.width - (padding * 2.0), maximumWidth),
                                   height: min(maximumHeight, size.height - (padding * 2.0)))

        // A wide creative's band has to be paid for out of the height the text and
        // call to action leave behind, so derive the width from that rather than
        // measuring the two independently — budgeting the band at one width and then
        // drawing it at another is what left it too short for its own shape, and
        // pillarboxed the creative inside it. A tall creative is already fitted by
        // height into whatever band remains, so narrowing the card would only squeeze
        // its text for no gain.
        let width: CGFloat
        if aspectRatio >= 1.0 {
            // Narrowing the card re-wraps the text, so measure again at the width we land on.
            let firstPass = Self.contentWidth(fitting: availableSize,
                                              aspectRatio: aspectRatio,
                                              chromeHeight: chromeHeight(forWidth: availableSize.width),
                                              maximumWidth: maximumWidth)
            width = Self.contentWidth(fitting: availableSize,
                                      aspectRatio: aspectRatio,
                                      chromeHeight: chromeHeight(forWidth: firstPass),
                                      maximumWidth: maximumWidth)
        } else {
            width = availableSize.width
        }

        let height = min(availableSize.height, chromeHeight(forWidth: width) + floor(width / aspectRatio))
        return CGSize(width: width, height: height)
    }
}

// MARK: - Layout Geometry

extension PromoNativeAdView {

    /// How the ad arranges its creative against its text.
    enum LayoutFormat {
        /// Text above, creative below, call to action at the foot. The media
        /// container spans the card, so a creative narrower than the card sits on
        /// blurred backdrop.
        case stacked
        /// The creative hugging its own aspect ratio on the trailing side, with the
        /// icon, headline, body and call to action stacked in the column beside it.
        case sideBySide
    }

    /// Whether a creative can be set beside its text rather than above it.
    ///
    /// This asks about the box, not the device. Its predecessor checked
    /// `verticalSizeClass == .compact` — true of a phone in landscape and never of an
    /// iPad, which is always regular height. So an iPad went on stacking portrait
    /// creatives however much width was going spare, and the surplus became blurred
    /// backdrop: on a landscape iPad, roughly two thirds of the media area.
    static func layoutFormat(containerSize: CGSize,
                             mediaAspectRatio: CGFloat,
                             minimumTextColumnWidth: CGFloat,
                             maximumMediaWidthFraction: CGFloat) -> LayoutFormat {
        // A wide creative already fills the card's width with nothing left over, and
        // an unresolved one — Google reports an aspect ratio of 0 until the media
        // content loads — has no shape to reason about. Both belong in the layout
        // that doesn't need to know.
        guard mediaAspectRatio > 0, mediaAspectRatio < 1.0 else { return .stacked }

        let media = mediaSize(fitting: containerSize,
                              aspectRatio: mediaAspectRatio,
                              maximumWidthFraction: maximumMediaWidthFraction)
        return (containerSize.width - media.width) >= minimumTextColumnWidth ? .sideBySide : .stacked
    }

    /// How much to grow the copy so it occupies `targetFill` of the column it sits in.
    ///
    /// Only ever grows. Overflow is already handled by a shrink-to-fit pass further
    /// down, and having two mechanisms pulling in opposite directions would make the
    /// result depend on which ran last.
    static func textScale(availableHeight: CGFloat,
                          naturalHeight: CGFloat,
                          targetFill: CGFloat,
                          maximumScale: CGFloat) -> CGFloat {
        guard naturalHeight > 0, availableHeight > 0 else { return 1.0 }
        return min(maximumScale, max(1.0, (availableHeight * targetFill) / naturalHeight))
    }

    /// The size a creative renders at inside a media band, preserving its shape.
    ///
    /// The previous version pinned a wide creative's width to the band and scaled only
    /// its height, which produced a media view wider than the creative. Google's
    /// `MediaView` then pillarboxed the creative inside it, and the gap read as grey
    /// wings either side of the video. Scaling both axes by the same factor is the
    /// whole fix; the scale is capped at 1 so a roomy band leaves space rather than
    /// blowing the creative up past its natural size.
    static func fittedMediaSize(containerSize: CGSize, aspectRatio: CGFloat) -> CGSize {
        guard aspectRatio > 0, containerSize.width > 0, containerSize.height > 0 else { return .zero }

        let natural = CGSize(width: containerSize.width, height: containerSize.width / aspectRatio)
        let scale = min(containerSize.width / natural.width, containerSize.height / natural.height)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    /// The width the card should take, given that its media band has to be paid for
    /// out of the height left over once the text and call to action have had theirs.
    ///
    /// Measuring width and height independently is what let the two disagree: the band
    /// was budgeted at `width / aspectRatio` for one width and then drawn at another,
    /// leaving it too short for its own shape. Deriving the width from the height the
    /// band can actually have keeps the two in step.
    static func contentWidth(fitting containerSize: CGSize,
                             aspectRatio: CGFloat,
                             chromeHeight: CGFloat,
                             maximumWidth: CGFloat) -> CGFloat {
        // No shape to reason about yet: fall back to the width alone.
        guard aspectRatio > 0 else { return min(containerSize.width, maximumWidth) }

        let bandHeight = max(0, containerSize.height - chromeHeight)
        return min(containerSize.width, maximumWidth, bandHeight * aspectRatio)
    }

    /// The size a creative renders at when set beside its text.
    ///
    /// It takes the container's full height until doing so would claim more than
    /// `maximumWidthFraction` of the card's width. Past that the creative yields
    /// rather than the text: it shrinks and gains vertical letterboxing, so the text
    /// column keeps its width and the text itself never scales down to fit.
    static func mediaSize(fitting containerSize: CGSize,
                          aspectRatio: CGFloat,
                          maximumWidthFraction: CGFloat) -> CGSize {
        guard aspectRatio > 0, containerSize.height > 0 else { return .zero }

        let fullHeightWidth = containerSize.height * aspectRatio
        let widthCap = containerSize.width * maximumWidthFraction
        guard fullHeightWidth > widthCap else {
            return CGSize(width: fullHeightWidth, height: containerSize.height)
        }
        return CGSize(width: widthCap, height: widthCap / aspectRatio)
    }
}
