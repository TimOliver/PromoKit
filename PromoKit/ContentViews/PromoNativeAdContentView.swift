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

    /// A blurred still image used behind the ad's media.
    public var mediaBackgroundImage: UIImage? {
        set { adView.mediaBackgroundImage = newValue }
        get { adView.mediaBackgroundImage }
    }

    /// The frame of the AdChoices info button, or zero if it is unavailable.
    public var adChoicesViewFrame: CGRect {
        adView.subviews.first(where: {
            NSStringFromClass(type(of: $0)).contains("GADNativeAdAttributionView")
        })?.frame ?? .zero
    }

    /// Maximum preferred card width.
    /// Forwarded from the provider; see `PromoNativeAdProvider.maximumContentWidth`.
    public var maximumContentWidth: CGFloat {
        set { adView.maximumWidth = newValue }
        get { adView.maximumWidth }
    }

    /// Maximum preferred card height.
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
        adView.mediaAspectRatioDidChange = { [weak self] in
            guard let self, let promoView = self.promoView,
                  promoView.contentView === self,
                  let provider = promoView.currentProvider else { return }
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
            promoView.invalidateIntrinsicContentSize()
            promoView.setNeedsLayout()
            // Let the host remeasure the existing card without rebinding its media.
            promoView.delegate?.promoView?(promoView, didUpdateProvider: provider)
        }
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

/// The inner `NativeAdView` that manages layout and Google AdMob events
/// for `PromoNativeAdContentView`.
final public class PromoNativeAdView: NativeAdView {

    /// A blurred backdrop visible where the media does not fill its container.
    public var mediaBackgroundImage: UIImage? {
        set { contentMediaContainerView.image = newValue }
        get { contentMediaContainerView.image }
    }

    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let adLabel = UILabel()
    private let actionButton = PromoNativeAdActionButton()
    private let iconImageView = UIImageView()
    private let contentMediaContainerView = UIImageView()
    private let contentMediaView = MediaView()

    // Track notifications separately from measurement, so sizeThatFits cannot
    // consume a ratio change before the host has been told to resize the card.
    var mediaAspectRatioDidChange: (() -> Void)?
    private var lastNotifiedAspectRatio: CGFloat = 1.0
    private weak var observedVideoController: VideoController?

    // Hide the SDK's test prefix in debug builds.
    private func headlineText(for nativeAd: NativeAd?) -> String {
#if DEBUG
        nativeAd?.headline?.replacingOccurrences(of: "Test mode: ", with: "") ?? ""
#else
        nativeAd?.headline ?? ""
#endif
    }

    // Fall back to the store and price when the ad has no body.
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
        stopObservingVideoPlayback()
        self.nativeAd = nil
        lastNotifiedAspectRatio = 1.0
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
        for view in [headlineLabel, bodyLabel, adLabel, actionButton, iconImageView,
                     contentMediaContainerView, contentMediaView] {
            view.frame = .zero
        }
        bodyLabel.isHidden = true
        iconImageView.isHidden = true
        actionButton.isHidden = true
    }

    /// Base point sizes before Dynamic Type and side-by-side fitting adjustments.
    private var baseHeadlineFontSize: CGFloat { 21.0 }
    private var baseBodyFontSize: CGFloat { 16.0 }

    /// The share of the text column the copy aims to occupy once grown.
    private var textColumnTargetFill: CGFloat { 0.5 }

    /// Maximum scale applied when growing copy into the text column.
    private var maximumTextScale: CGFloat { 1.8 }

    /// Reapplies fonts on each layout pass so reuse and layout changes cannot retain
    /// a previous arrangement's text scale.
    private func applyTextFonts(scale: CGFloat) {
        let fonts = textFonts(scale: scale)
        headlineLabel.font = fonts.headline
        bodyLabel.font = fonts.body
    }

    private func textFonts(scale: CGFloat) -> (headline: UIFont, body: UIFont) {
        let headline = UIFont.systemFont(ofSize: baseHeadlineFontSize * scale, weight: .bold)
        let body = UIFont.systemFont(ofSize: baseBodyFontSize * scale)
        return (UIFontMetrics.default.scaledFont(for: headline),
                UIFontMetrics.default.scaledFont(for: body))
    }

    private func headlineStyle(indent: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.baseWritingDirection = isRightToLeft ? .rightToLeft : .leftToRight
        return style
    }

    private var isRightToLeft: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }

    private func configureContentViews() {
        applyTextFonts(scale: 1.0)
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

        stopObservingVideoPlayback()
        let videoController = nativeAd.mediaContent.videoController
        observedVideoController = videoController
        videoController.delegate = self

        iconImageView.image = nativeAd.icon?.image

        if let body = bodyText(for: nativeAd) {
            bodyLabel.attributedText = NSAttributedString(string: body)
        }

        contentMediaContainerView.image = mediaBackgroundImage
        contentMediaView.mediaContent = nativeAd.mediaContent
        lastNotifiedAspectRatio = Self.usableAspectRatio(for: nativeAd)

        actionButton.title = nil
        if let cta = nativeAd.callToAction {
            actionButton.title = cta.capitalized
        }

        // Size and arrange asset views before registering the ad with the SDK.
        frame.size = sizeThatFits(CGSize(width: 1000, height: 1000), nativeAd: nativeAd)
        layoutSubviews(for: nativeAd)

        self.nativeAd = nativeAd
        updateMediaAspectRatioIfNeeded()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutSubviews(for: self.nativeAd)
    }

    public func layoutSubviews(for nativeAd: NativeAd?) {
        super.layoutSubviews()

        guard let nativeAd else { return }

        let size = frame.insetBy(dx: padding, dy: padding).size
        let aspectRatio = Self.usableAspectRatio(for: nativeAd)

        let format = Self.layoutFormat(containerSize: size,
                                       mediaAspectRatio: aspectRatio,
                                       minimumTextColumnWidth: minimumTextColumnWidth,
                                       maximumMediaWidthFraction: maximumMediaWidthFraction)
        switch format {
        case .sideBySide:
            layoutSubviewsInLandscapeFormat(size: size, nativeAd: nativeAd)
        case .stacked:
            layoutSubviewsInPortraitFormat(size: size, nativeAd: nativeAd)
        }

        if isRightToLeft {
            mirrorContent(for: format, size: size)
        }

        // Register asset views after layout so SDK validation sees their final frames.
        self.headlineView = headlineLabel
        self.bodyView = !bodyLabel.isHidden ? bodyLabel : nil
        self.iconView = !iconImageView.isHidden ? iconImageView : nil
        self.mediaView = contentMediaView
        self.callToActionView = !actionButton.isHidden ? actionButton : nil

        if self.nativeAd === nativeAd {
            updateMediaAspectRatioIfNeeded()
        }
    }

    private func mirrorContent(for format: LayoutFormat, size: CGSize) {
        // AdChoices stays at the SDK's physical top-right corner. Mirror only
        // our asset frames within the width left beside that reservation.
        var mirroredViews: [UIView] = [headlineLabel, bodyLabel, adLabel, iconImageView]
        if format == .sideBySide {
            mirroredViews += [actionButton, contentMediaContainerView]
        } else if needsCompactLayout, !actionButton.isHidden {
            actionButton.frame.origin.x = size.width - actionButton.frame.maxX
        }
        for view in mirroredViews where !view.isHidden && view.superview === self {
            view.frame.origin.x = size.width - googleButtonWidth - view.frame.maxX
        }
    }

    private func layoutSubviewsInLandscapeFormat(size: CGSize, nativeAd: NativeAd) {
        let aspectRatio = Self.usableAspectRatio(for: nativeAd)
        // Reserve text-column width by limiting the media's share of the card.
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

        let mediaTotalWidth = (mediaWidth + googleButtonWidth + padding + innerMargin)
        let textContentSize = CGSize(width: size.width - mediaTotalWidth,
                                     height: size.height)

        // The icon is sized with the copy below.
        iconImageView.isHidden = (iconImageView.image == nil)
        if iconImageView.isHidden {
            iconImageView.frame = .zero
            iconImageView.removeFromSuperview()
        } else if iconImageView.superview == nil {
            addSubview(iconImageView)
        }

        actionButton.isHidden = actionButton.title?.isEmpty ?? true
        if !actionButton.isHidden {
            actionButton.tintColor = self.tintColor
            let buttonSize = CGSize(width: textContentSize.width, height: ctaButtonHeight)
            let buttonOrigin = CGPoint(x: padding, y: size.height - (ctaButtonHeight + padding))
            actionButton.frame = CGRect(origin: buttonOrigin, size: buttonSize)
            if actionButton.superview == nil { insertSubview(actionButton, at: 0) }
        } else {
            actionButton.frame = .zero
            actionButton.removeFromSuperview()
        }

        // The column the icon and copy share, from the card's top down to the button.
        let columnTop = padding
        let columnBottom = actionButton.isHidden ? (size.height - padding)
                                                 : actionButton.frame.minY - innerMargin
        let remainingTextSize = CGSize(width: textContentSize.width,
                                       height: columnBottom - columnTop)

        let bodyString = bodyText(for: nativeAd)

        // Measure at the base fonts before growing into available space or shrinking to fit.
        applyTextFonts(scale: 1.0)
        // Measure all body lines; the column's height constrains the final layout.
        bodyLabel.numberOfLines = 0
        headlineLabel.attributedText = NSAttributedString(string: headlineText(for: nativeAd),
                                                          attributes: [.paragraphStyle: headlineStyle(indent: 0)])
        bodyLabel.text = bodyString
        var naturalTextHeight = headlineLabel.sizeThatFits(remainingTextSize).height
        if !(bodyString?.isEmpty ?? true) {
            naturalTextHeight += titleVerticalSpacing + bodyLabel.sizeThatFits(remainingTextSize).height
        }
        if !iconImageView.isHidden { naturalTextHeight += iconHeight + titleVerticalSpacing }
        var textScale = Self.textScale(availableHeight: remainingTextSize.height,
                                      naturalHeight: naturalTextHeight,
                                      targetFill: textColumnTargetFill,
                                      maximumScale: maximumTextScale)
        applyTextFonts(scale: textScale)

        headlineLabel.textAlignment = .center
        headlineLabel.frame.size = headlineLabel.sizeThatFits(remainingTextSize)

        adLabel.frame.size = adLabelSize
        adLabel.frame.origin = CGPoint(x: 7, y: 3)
        adLabel.textColor = backgroundColor

        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true
        if !bodyLabel.isHidden {
            if bodyLabel.superview == nil { addSubview(bodyLabel) }
            bodyLabel.textAlignment = .center
            bodyLabel.frame.size = bodyLabel.sizeThatFits(remainingTextSize)
        } else {
            bodyLabel.frame = .zero
            bodyLabel.removeFromSuperview()
        }

        // Fit the icon and copy together above the call to action.
        let naturalSpacing = (bodyLabel.isHidden ? 0 : titleVerticalSpacing)
            + (iconImageView.isHidden ? 0 : titleVerticalSpacing)
        let naturalBlockHeight = headlineLabel.frame.height
            + (bodyLabel.isHidden ? 0 : bodyLabel.frame.height)
            + (iconImageView.isHidden ? 0 : iconHeight * textScale)
        let availableHeight = max(0, remainingTextSize.height)
        if naturalBlockHeight + naturalSpacing > availableHeight, naturalBlockHeight > 0 {
            let shrink = max(minimumTextShrink,
                             max(0, availableHeight - naturalSpacing) / naturalBlockHeight)
            textScale *= shrink
            applyTextFonts(scale: textScale)
            headlineLabel.frame.size = headlineLabel.sizeThatFits(remainingTextSize)
            if !bodyLabel.isHidden {
                bodyLabel.frame.size = bodyLabel.sizeThatFits(remainingTextSize)
            }
        }

        // If even the minimum readable fonts cannot fit, truncate the copy to
        // its column and give the icon only the space left above it.
        headlineLabel.frame.size.height = min(headlineLabel.frame.height, availableHeight)
        let bodySpacing = bodyLabel.isHidden ? 0
            : min(titleVerticalSpacing, max(0, availableHeight - headlineLabel.frame.height))
        if !bodyLabel.isHidden {
            bodyLabel.frame.size.height = min(bodyLabel.frame.height,
                                              max(0, availableHeight - headlineLabel.frame.height - bodySpacing))
        }
        let copyHeight = headlineLabel.frame.height
            + (bodyLabel.isHidden ? 0 : bodySpacing + bodyLabel.frame.height)

        // Apply the final scale to the icon too, including any shrink above.
        var iconSize = CGSize.zero
        if !iconImageView.isHidden, let icon = nativeAd.icon?.image {
            let iconAspectRatio = icon.size.width / icon.size.height
            let scaledHeight = min(iconHeight * textScale,
                                   max(0, availableHeight - copyHeight - titleVerticalSpacing))
            iconSize = CGSize(width: scaledHeight * iconAspectRatio, height: scaledHeight)
        }

        // Centre the icon and copy as one block, keeping extra space outside it.
        var blockHeight = copyHeight
        if iconSize.height > 0 { blockHeight += iconSize.height + titleVerticalSpacing }

        var blockOriginY = columnTop + max(0.0, (remainingTextSize.height - blockHeight) * 0.5)

        if iconSize.height > 0 {
            iconImageView.frame = pixelAligned(CGRect(x: (remainingTextSize.width - iconSize.width) * 0.5,
                                                      y: blockOriginY,
                                                      width: iconSize.width,
                                                      height: iconSize.height))
            iconImageView.layer.cornerRadius = iconSize.height * 0.23
            blockOriginY = iconImageView.frame.maxY + titleVerticalSpacing
        } else {
            iconImageView.frame = .zero
        }

        headlineLabel.frame.origin = CGPoint(x: (remainingTextSize.width - headlineLabel.frame.width) * 0.5,
                                             y: blockOriginY)

        if bodyLabel.isHidden { return }

        bodyLabel.frame.origin = CGPoint(x: (remainingTextSize.width - bodyLabel.frame.width) * 0.5,
                                         y: headlineLabel.frame.maxY + bodySpacing)
    }

    private func layoutSubviewsInPortraitFormat(size: CGSize, nativeAd: NativeAd) {
        // Reset fonts and line limits after reuse or a side-by-side layout.
        applyTextFonts(scale: 1.0)
        bodyLabel.numberOfLines = needsCompactLayout ? 2 : 3
        var origin = CGPoint(x: padding, y: padding)

        var iconSize = CGSize.zero
        iconImageView.isHidden = iconImageView.image == nil
        if !iconImageView.isHidden, let icon = nativeAd.icon?.image {
            if iconImageView.superview == nil { addSubview(iconImageView) }
            let aspectRatio = icon.size.width / icon.size.height
            iconSize = CGSize(width: iconHeight * aspectRatio, height: iconHeight)
            iconImageView.frame = pixelAligned(CGRect(origin: origin, size: iconSize))
            iconImageView.layer.cornerRadius = iconSize.height * 0.23
        } else {
            iconImageView.frame = .zero
            iconImageView.removeFromSuperview()
        }

        bodyLabel.text = bodyText(for: nativeAd)
        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true

        let textX = iconImageView.isHidden ? padding : iconSize.width + innerMargin
        let textWidth = size.width - (textX + googleButtonWidth + (padding * 2.0) + (needsCompactLayout ? compactActionSize.width : 0.0))
        let textFittingSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

        headlineLabel.attributedText = NSAttributedString(string: headlineText(for: nativeAd),
                                                          attributes: [.paragraphStyle: headlineStyle(indent: headlineIndent)])

        headlineLabel.textAlignment = isRightToLeft ? .right : .left
        headlineLabel.frame.size = headlineLabel.sizeThatFits(textFittingSize)
        bodyLabel.frame.size = bodyLabel.isHidden ? .zero : bodyLabel.sizeThatFits(textFittingSize)
        let totalTextHeight = headlineLabel.frame.height + titleVerticalSpacing + bodyLabel.frame.height

        let textY = totalTextHeight < iconSize.height ? (iconSize.height - totalTextHeight) / 2.0 : padding
        headlineLabel.frame.origin = CGPoint(x: textX, y: textY)

        // Place the badge in the headline's first-line indent.
        adLabel.frame.size = adLabelSize
        adLabel.frame.origin = CGPoint(x: headlineLabel.frame.minX,
                                       y: headlineLabel.frame.minY + adLabelOffset)
        adLabel.textColor = backgroundColor

        if !bodyLabel.isHidden {
            if bodyLabel.superview == nil { addSubview(bodyLabel) }
            let textY = headlineLabel.frame.maxY + titleVerticalSpacing
            bodyLabel.frame.origin = CGPoint(x: textX, y: textY)
            bodyLabel.textAlignment = isRightToLeft ? .right : .left
        } else {
            bodyLabel.frame = .zero
            bodyLabel.removeFromSuperview()
        }

        let iconBottom = iconImageView.isHidden ? 0 : iconImageView.frame.maxY
        let bodyBottom = bodyLabel.isHidden ? 0 : bodyLabel.frame.maxY
        origin.y = max(iconBottom, max(headlineLabel.frame.maxY, bodyBottom)) + innerMargin

        actionButton.isHidden = actionButton.title?.isEmpty ?? true
        if !actionButton.isHidden {
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
            actionButton.frame = .zero
            actionButton.removeFromSuperview()
        }

        if needsCompactLayout, !actionButton.isHidden {
            origin.y = max(origin.y, actionButton.frame.maxY + innerMargin)
        }

        let aspectRatio = Self.usableAspectRatio(for: nativeAd)
        let actionButtonY = (actionButton.superview != nil && !needsCompactLayout) ? (actionButton.frame.minY - innerMargin) : size.height
        let mediaContainerSize = CGSize(width: size.width, height: actionButtonY - origin.y)
        contentMediaContainerView.frame = pixelAligned(CGRect(origin: CGPoint(x: padding, y: origin.y),
                                                              size: mediaContainerSize))
        contentMediaContainerView.layer.cornerRadius = 15.0
        updateMediaViewBackgroundColor()

        // Preserve the media's ratio and snap its edges to avoid hairline gaps.
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

    private func stopObservingVideoPlayback() {
        if observedVideoController?.delegate === self {
            observedVideoController?.delegate = nil
        }
        observedVideoController = nil
    }

    /// A still supplies the initial shape; SDK media dimensions take over when
    /// available. Playback and layout are opportunities to discover that change,
    /// since Google provides no dedicated media-metadata readiness callback.
    private func updateMediaAspectRatioIfNeeded() {
        guard let nativeAd else { return }
        let aspectRatio = Self.usableAspectRatio(for: nativeAd)
        guard aspectRatio != lastNotifiedAspectRatio else { return }
        lastNotifiedAspectRatio = aspectRatio
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        mediaAspectRatioDidChange?()
    }

    // Layout dimensions and limits.
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

    /// Rounds edges independently so adjoining views meet without pixel gaps.
    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let minX = pixelAligned(rect.minX), minY = pixelAligned(rect.minY)
        let maxX = pixelAligned(rect.maxX), maxY = pixelAligned(rect.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private var iconHeight: CGFloat { 64.0 }

    /// Fits localized button text within a 120–200-point width to preserve room for copy.
    private var compactActionSize: CGSize {
        let height: CGFloat = 40
        return CGSize(width: min(max(120, actionButton.widthThatFits(height: height)), 200),
                      height: height)
    }

    /// Minimum fitting scale before truncating copy to the available height.
    private var minimumTextShrink: CGFloat { 0.6 }

    /// Minimum text-column width required for a side-by-side layout.
    private var minimumTextColumnWidth: CGFloat { 240.0 }

    /// The most of the card's width a creative may claim when set beside its text.
    private var maximumMediaWidthFraction: CGFloat { 0.55 }

    /// Measures the ad within the supplied size and configured limits.
    /// - Parameter size: Size constraining the ad view
    /// - Returns: Resulting size of the ad view
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        sizeThatFits(size, nativeAd: self.nativeAd)
    }

    private func sizeThatFits(_ size: CGSize, nativeAd: NativeAd?) -> CGSize {
        guard let nativeAd else { return .zero }

        let aspectRatio = Self.usableAspectRatio(for: nativeAd)

        // Apply size limits before selecting the layout arrangement.
        let availableSize = CGSize(width: max(0, min(size.width - (padding * 2.0), maximumWidth)),
                                   height: max(0, min(size.height - (padding * 2.0), maximumHeight)))
        guard availableSize.width > 0, availableSize.height > 0 else { return .zero }

        // Measurement and layout must select the same arrangement.
        let contentBox = CGSize(width: availableSize.width - (padding * 2.0),
                                height: availableSize.height - (padding * 2.0))
        let isHorizontalLayout = Self.layoutFormat(containerSize: contentBox,
                                                   mediaAspectRatio: aspectRatio,
                                                   minimumTextColumnWidth: minimumTextColumnWidth,
                                                   maximumMediaWidthFraction: maximumMediaWidthFraction) == .sideBySide
        if isHorizontalLayout {
            let height = availableSize.height
            let mediaWidth = (height * aspectRatio) + innerMargin
            let adjustedWidth = min(availableSize.width, mediaWidth + 375)
            return CGSize(width: adjustedWidth, height: height)
        }

        var iconSize = CGSize.zero
        if let icon = nativeAd.icon?.image {
            let iconAspectRatio = icon.size.width / icon.size.height
            iconSize = CGSize(width: iconHeight * iconAspectRatio, height: iconHeight)
        }

        // Visible labels may retain another arrangement's fonts until the next
        // layout pass, so measure the stacked style independently.
        let fonts = textFonts(scale: 1.0)
        let measuredHeadline = UILabel()
        measuredHeadline.font = fonts.headline
        measuredHeadline.numberOfLines = 2
        measuredHeadline.attributedText = NSAttributedString(string: headlineText(for: nativeAd),
                                                             attributes: [.paragraphStyle: headlineStyle(indent: headlineIndent)])
        let body = bodyText(for: nativeAd)
        let measuredBody = UILabel()
        measuredBody.font = fonts.body
        measuredBody.numberOfLines = needsCompactLayout ? 2 : 3
        measuredBody.text = body

        // Height reserved for text, icon, call to action, and spacing.
        func chromeHeight(forWidth cardWidth: CGFloat) -> CGFloat {
            var textWidth = cardWidth - ((iconSize.width > 0.0 ? innerMargin + iconSize.width : 0.0) + googleButtonWidth)
            if needsCompactLayout { textWidth -= (innerMargin + compactActionSize.width) }
            let textSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

            var textHeight = measuredHeadline.sizeThatFits(textSize).height
            if body != nil {
                textHeight += titleVerticalSpacing + measuredBody.sizeThatFits(textSize).height
            }

            var headerHeight = max(textHeight, iconSize.height)
            if needsCompactLayout, !(nativeAd.callToAction?.isEmpty ?? true) {
                // Reserve the inline button's height below AdChoices.
                headerHeight = max(headerHeight,
                                   googleButtonWidth + titleVerticalSpacing + compactActionSize.height)
            }
            var chrome = (padding * 2.0) + headerHeight + innerMargin
            if !needsCompactLayout { chrome += innerMargin + ctaButtonHeight }
            return chrome
        }

        // Wide media constrains the card width through its available height.
        // Tall media fits within the remaining band without narrowing the text.
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

// MARK: - Video Playback

extension PromoNativeAdView: VideoControllerDelegate {
    public func videoControllerDidPlayVideo(_ videoController: VideoController) {
        guard observedVideoController === videoController,
              nativeAd?.mediaContent.videoController === videoController else { return }
        updateMediaAspectRatioIfNeeded()
    }
}

// MARK: - Layout Geometry

extension PromoNativeAdView {

    /// How the ad arranges its creative against its text.
    enum LayoutFormat {
        /// Text above the media, with the call to action below or inline in compact height.
        case stacked
        /// Media on the right, with icon, copy, and call to action beside it.
        case sideBySide
    }

    /// Selects a side-by-side layout for portrait media when the container leaves
    /// enough width for the text column, independently of device size classes.
    static func layoutFormat(containerSize: CGSize,
                             mediaAspectRatio: CGFloat,
                             minimumTextColumnWidth: CGFloat,
                             maximumMediaWidthFraction: CGFloat) -> LayoutFormat {
        // Square, wide, and unknown media ratios use the stacked layout.
        guard mediaAspectRatio > 0, mediaAspectRatio < 1.0 else { return .stacked }

        let media = mediaSize(fitting: containerSize,
                              aspectRatio: mediaAspectRatio,
                              maximumWidthFraction: maximumMediaWidthFraction)
        return (containerSize.width - media.width) >= minimumTextColumnWidth ? .sideBySide : .stacked
    }

    /// Grows copy toward `targetFill`, up to `maximumScale`.
    /// Layout handles overflow separately after measuring the scaled fonts.
    static func textScale(availableHeight: CGFloat,
                          naturalHeight: CGFloat,
                          targetFill: CGFloat,
                          maximumScale: CGFloat) -> CGFloat {
        guard naturalHeight > 0, availableHeight > 0 else { return 1.0 }
        return min(maximumScale, max(1.0, (availableHeight * targetFill) / naturalHeight))
    }

    /// A usable layout ratio, preferring SDK metadata, then a still, then a square.
    ///
    /// Google's ratio can be zero when unknown or when there is no media. Neither
    /// a later update nor a still matching the video's shape is guaranteed.
    static func usableAspectRatio(reported: CGFloat, stillSize: CGSize?) -> CGFloat {
        if reported.isFinite, reported > 0.0 { return reported }
        if let stillSize,
           stillSize.width.isFinite, stillSize.width > 0.0,
           stillSize.height.isFinite, stillSize.height > 0.0 {
            let ratio = stillSize.width / stillSize.height
            if ratio.isFinite, ratio > 0.0 { return ratio }
        }
        return 1.0
    }

    /// Prefers the media's main image, falling back to the first supplied still.
    static func stillSize(for nativeAd: NativeAd) -> CGSize? {
        nativeAd.mediaContent.mainImage?.size ?? nativeAd.images?.first?.image?.size
    }

    static func usableAspectRatio(for nativeAd: NativeAd) -> CGFloat {
        usableAspectRatio(reported: nativeAd.mediaContent.aspectRatio, stillSize: stillSize(for: nativeAd))
    }

    /// Fit the creative inside the media band while preserving its layout ratio.
    static func fittedMediaSize(containerSize: CGSize, aspectRatio: CGFloat) -> CGSize {
        guard aspectRatio > 0, containerSize.width > 0, containerSize.height > 0 else { return .zero }

        let natural = CGSize(width: containerSize.width, height: containerSize.width / aspectRatio)
        let scale = min(containerSize.width / natural.width, containerSize.height / natural.height)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    /// Derives card width from the height available to media after reserving the
    /// text and controls, keeping media measurement consistent with its aspect ratio.
    static func contentWidth(fitting containerSize: CGSize,
                             aspectRatio: CGFloat,
                             chromeHeight: CGFloat,
                             maximumWidth: CGFloat) -> CGFloat {
        // No shape to reason about yet: fall back to the width alone.
        guard aspectRatio > 0 else { return min(containerSize.width, maximumWidth) }

        let bandHeight = max(0, containerSize.height - chromeHeight)
        return min(containerSize.width, maximumWidth, bandHeight * aspectRatio)
    }

    /// Fits media to the container height, capped at `maximumWidthFraction` of its
    /// width, preserving both the media ratio and space for the text column.
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
