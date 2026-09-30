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

    // Track notifications separately from measurement, so sizeThatFits cannot
    // consume a ratio change before the host has been told to resize the card.
    var mediaAspectRatioDidChange: (() -> Void)?
    private var lastNotifiedAspectRatio: CGFloat = 1.0
    private weak var observedVideoController: VideoController?

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

    /// Base point sizes for the copy. The side-by-side layout scales up from these
    /// when the column has room; everything else uses them as-is.
    private var baseHeadlineFontSize: CGFloat { 21.0 }
    private var baseBodyFontSize: CGFloat { 16.0 }

    /// The share of the text column the copy aims to occupy once grown.
    private var textColumnTargetFill: CGFloat { 0.5 }

    /// How far the copy may grow. Past this the headline stops reading as a headline.
    private var maximumTextScale: CGFloat { 1.8 }

    /// Re-applies the copy's fonts at `scale`. Called on every layout pass, including
    /// with 1.0, because content views are recycled — a view that grew its text beside
    /// a tall creative would otherwise keep those sizes when reused for a stacked one.
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
        return style
    }

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

        // Force a layout to ensure the elements are appropriately sized
        frame.size = sizeThatFits(CGSize(width: 1000, height: 1000), nativeAd: nativeAd)
        layoutSubviews(for: nativeAd)

        // Set the ad after everything else is set
        self.nativeAd = nativeAd
        updateMediaAspectRatioIfNeeded()
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
        let aspectRatio = Self.usableAspectRatio(for: nativeAd)

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
        self.callToActionView = !actionButton.isHidden ? actionButton : nil

        if self.nativeAd === nativeAd {
            updateMediaAspectRatioIfNeeded()
        }
    }

    private func layoutSubviewsInLandscapeFormat(size: CGSize, nativeAd: NativeAd) {
        // Lay out the ad view on the right hand side
        let aspectRatio = Self.usableAspectRatio(for: nativeAd)
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

        // The icon is sized and placed further down, with the copy: it belongs to the
        // same block rather than floating at a fixed fraction of the column's height.
        iconImageView.isHidden = (iconImageView.image == nil)
        if iconImageView.isHidden {
            iconImageView.frame = .zero
            iconImageView.removeFromSuperview()
        } else if iconImageView.superview == nil {
            addSubview(iconImageView)
        }

        // Layout the action button at the bottom
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

        // Measure the copy at its base sizes, then grow it into the column. Beside a
        // tall creative the column is far taller than two lines of headline and three
        // of body need, which left the copy stranded at the top with the button at the
        // foot and most of the column empty. A short column scales by 1 and is unchanged.
        applyTextFonts(scale: 1.0)
        // The column is tall, so let the body wrap as far as it needs. Capped at three
        // lines it ran out of lines rather than space once grown, and truncated with an
        // ellipsis while the space below it went unused. The scale is derived from the
        // measured height, so freeing the line count is what makes that measurement true.
        bodyLabel.numberOfLines = 0
        headlineLabel.attributedText = NSAttributedString(string: headlineText(for: nativeAd),
                                                          attributes: [.paragraphStyle: headlineStyle(indent: 0)])
        bodyLabel.text = bodyString
        var naturalTextHeight = headlineLabel.sizeThatFits(remainingTextSize).height
        if !(bodyString?.isEmpty ?? true) {
            naturalTextHeight += titleVerticalSpacing + bodyLabel.sizeThatFits(remainingTextSize).height
        }
        if !iconImageView.isHidden { naturalTextHeight += iconHeight + titleVerticalSpacing }
        let textScale = Self.textScale(availableHeight: remainingTextSize.height,
                                       naturalHeight: naturalTextHeight,
                                       targetFill: textColumnTargetFill,
                                       maximumScale: maximumTextScale)
        applyTextFonts(scale: textScale)

        // Lay out the title
        headlineLabel.textAlignment = .center
        headlineLabel.frame.size = headlineLabel.sizeThatFits(remainingTextSize)

        // Lay out the ad label
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

        // Shrink the copy if it overflows its column. The previous version scaled the
        // labels' frame heights, which does not make the text any smaller — it only
        // gives it less room to draw in, so it clipped. Reducing the font is what
        // actually fits it. Floored, because past a point the copy is unreadable and
        // the shrink-to-fit is doing more harm than the overflow it is avoiding.
        let naturalCopyHeight = headlineLabel.frame.height
            + (bodyLabel.isHidden ? 0.0 : titleVerticalSpacing + bodyLabel.frame.height)
        if naturalCopyHeight > remainingTextSize.height, naturalCopyHeight > 0 {
            let shrink = max(minimumTextShrink, remainingTextSize.height / naturalCopyHeight)
            applyTextFonts(scale: textScale * shrink)
            headlineLabel.frame.size = headlineLabel.sizeThatFits(remainingTextSize)
            if !bodyLabel.isHidden {
                bodyLabel.frame.size = bodyLabel.sizeThatFits(remainingTextSize)
            }
        }

        // Size the icon with the copy, so it keeps its proportion as the text grows
        // rather than shrinking away beside it.
        var iconSize = CGSize.zero
        if !iconImageView.isHidden, let icon = nativeAd.icon?.image {
            let iconAspectRatio = icon.size.width / icon.size.height
            let scaledHeight = iconHeight * textScale
            iconSize = CGSize(width: scaledHeight * iconAspectRatio, height: scaledHeight)
        }

        // Icon, headline and body are one block, centred together. Whatever slack the
        // growth cap leaves sits either side of that block, not between its parts.
        var blockHeight = headlineLabel.frame.height
        if !bodyLabel.isHidden { blockHeight += titleVerticalSpacing + bodyLabel.frame.height }
        if iconSize.height > 0 { blockHeight += iconSize.height + titleVerticalSpacing }

        var blockOriginY = columnTop + max(0.0, (remainingTextSize.height - blockHeight) * 0.5)

        if iconSize.height > 0 {
            iconImageView.frame = pixelAligned(CGRect(x: (remainingTextSize.width - iconSize.width) * 0.5,
                                                      y: blockOriginY,
                                                      width: iconSize.width,
                                                      height: iconSize.height))
            iconImageView.layer.cornerRadius = iconSize.height * 0.23
            blockOriginY = iconImageView.frame.maxY + titleVerticalSpacing
        }

        headlineLabel.frame.origin = CGPoint(x: (remainingTextSize.width - headlineLabel.frame.width) * 0.5,
                                             y: blockOriginY)

        // We're done if the label is hidden
        if bodyLabel.isHidden { return }

        // Lay out the subtitle
        bodyLabel.frame.origin = CGPoint(x: (remainingTextSize.width - bodyLabel.frame.width) * 0.5,
                                         y: headlineLabel.frame.maxY + titleVerticalSpacing)

    }

    private func layoutSubviewsInPortraitFormat(size: CGSize, nativeAd: NativeAd) {
        // Recycled views may arrive with the side-by-side layout's grown fonts and its
        // unbounded line count.
        applyTextFonts(scale: 1.0)
        bodyLabel.numberOfLines = needsCompactLayout ? 2 : 3
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
            iconImageView.frame = .zero
            iconImageView.removeFromSuperview()
        }

        // Hide the body if we don't have any text
        bodyLabel.text = bodyText(for: nativeAd)
        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true

        // Position the title text
        let textX = iconImageView.isHidden ? padding : iconSize.width + innerMargin
        let textWidth = size.width - (textX + googleButtonWidth + (padding * 2.0) + (needsCompactLayout ? compactActionSize.width : 0.0))
        let textFittingSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

        headlineLabel.attributedText = NSAttributedString(string: headlineText(for: nativeAd),
                                                          attributes: [.paragraphStyle: headlineStyle(indent: headlineIndent)])

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

        // Position the media container
        let aspectRatio = Self.usableAspectRatio(for: nativeAd)
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
    /// The compact call to action, sized to its own text. A fixed width fitted some
    /// of Google's calls to action and clipped others — "Install" and
    /// "今すぐダウンロード" are not the same size, and shrink-to-fit only rescues the
    /// near misses. Floored at the original width so short ones keep their shape, and
    /// capped so a long one cannot crowd the copy out of an already compact card.
    private var compactActionSize: CGSize {
        let height: CGFloat = 40
        return CGSize(width: min(max(120, actionButton.widthThatFits(height: height)), 200),
                      height: height)
    }

    /// How far the copy may shrink to fit its column before losing a line is the
    /// better trade.
    private var minimumTextShrink: CGFloat { 0.6 }

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
        let aspectRatio = Self.usableAspectRatio(for: nativeAd)

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

        // Measure the stacked style independently of the visible labels. They
        // may still use enlarged fonts from a side-by-side still while the host
        // is measuring the newly available video, before its next layout pass.
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

        // Everything the card owes before the media band is given any height at all.
        func chromeHeight(forWidth cardWidth: CGFloat) -> CGFloat {
            var textWidth = cardWidth - ((iconSize.width > 0.0 ? innerMargin + iconSize.width : 0.0) + googleButtonWidth)
            if needsCompactLayout { textWidth -= (innerMargin + compactActionSize.width) }
            let textSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

            var textHeight = measuredHeadline.sizeThatFits(textSize).height
            if body != nil {
                textHeight += titleVerticalSpacing + measuredBody.sizeThatFits(textSize).height
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
        // A wide creative already fills the card's width with nothing left over.
        // An unknown ratio also belongs in the layout that doesn't need its shape.
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

    /// The creative's own still, if one shipped with the ad. `mainImage` covers
    /// image creatives; `images` is the asset a video creative is served with,
    /// and is already what the blurred backdrop is built from.
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
