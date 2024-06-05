//
//  PromoNativeAdContentView.swift
//  PromoKitExample
//
//  Created by Tim Oliver on 8/5/2024.
//

import Foundation
import GoogleMobileAds

final public class PromoNativeAdView: GADNativeAdView {

    // The native ad model object driving this ad view
    public override var nativeAd: GADNativeAd? {
        didSet { updateAdContent() }
    }

    // A generated blurred image placed behind the ad when the aspect ratio
    // doesn't align
    public var mediaBackgroundImage: UIImage? {
        didSet { updateAdContent() }
    }

    // Main, bold headline title shown at the top
    private let headlineLabel = UILabel()

    // Any auxiliary body text
    private let bodyLabel = UILabel()

    // A large call-to-action button shown at the bottom
    private let actionButton = UIButton(type: .system)

    // An icon image view optionally shown next to the headline
    private let iconImageView = UIImageView()

    // A container view hosting the media view
    private let contentMediaContainerView = UIImageView()

    // If media, the content view used to show the media
    private let contentMediaView = GADMediaView()

    // Track when the first size has occurred so we can defer configuring the ad content until then
    private var didSizeToAdContent = false

    // For easier testing, remove the 'Test mode' string from the title
    private var headlineText: String {
#if DEBUG
        nativeAd?.headline?.replacingOccurrences(of: "Test mode: ", with: "") ?? ""
#else
        nativeAd?.headline ?? ""
#endif
    }

    // If a body string was supplied, show that. If not, show the name of the store,
    // and the price as a string instead
    private var bodyText: String? {
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
        // Detach the views from the Google references until the next layout pass
        self.headlineView = nil
        self.bodyView = nil
        self.iconView = nil
        self.mediaView = nil
        self.callToActionView = nil

        headlineLabel.attributedText = nil
        bodyLabel.attributedText = nil
        actionButton.setTitle(nil, for: .normal)
        contentMediaView.mediaContent = nil
        mediaBackgroundImage = nil

        didSizeToAdContent = false
    }

    private func configureContentViews() {
        let headlineFont = UIFont.systemFont(ofSize: 21, weight: .bold)
        headlineLabel.font = UIFontMetrics.default.scaledFont(for: headlineFont)
        headlineLabel.adjustsFontSizeToFitWidth = true
        headlineLabel.minimumScaleFactor = 0.75
        headlineLabel.numberOfLines = 2
        addSubview(headlineLabel)

        let bodyFont = UIFont.systemFont(ofSize: 16.0)
        bodyLabel.font = UIFontMetrics.default.scaledFont(for: bodyFont)
        bodyLabel.numberOfLines = 3
        bodyLabel.adjustsFontSizeToFitWidth = true
        bodyLabel.minimumScaleFactor = 0.35
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

        actionButton.isUserInteractionEnabled = false
        actionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18.0)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.clipsToBounds = true
        if #available(iOS 13.0, *) {
            actionButton.layer.cornerCurve = .continuous
        }
        insertSubview(actionButton, at: 0)
    }

    private func updateAdContent() {
        iconImageView.image = nativeAd?.icon?.image
        headlineLabel.attributedText = NSAttributedString(string: headlineText)
        if let body = bodyText {
            bodyLabel.attributedText = NSAttributedString(string: body)
        }

        contentMediaContainerView.image = mediaBackgroundImage
        contentMediaView.mediaContent = nativeAd?.mediaContent

        actionButton.setTitle(nil, for: .normal)
        if let cta = nativeAd?.callToAction {
            actionButton.setTitle(cta.capitalized, for: .normal)
        }

        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Skip layout if we don't have an ad yet
        guard didSizeToAdContent, let nativeAd else { return }

        let size = frame.insetBy(dx: padding, dy: padding).size
        let aspectRatio = nativeAd.mediaContent.aspectRatio

        // Layout horizontally on very tightly constrained sizes
        if needsCompactLayout, aspectRatio < 1.0 {
            layoutSubviewsInLandscapeFormat(size: size)
        } else {
            layoutSubviewsInPortraitFormat(size: size)
        }

        // Once all the views are configured, connect them to Google's references.
        // We defer them this late since it seems Google's validator occurs when they are
        // connected, so they must be in their final resting position by then
        self.headlineView = headlineLabel
        self.bodyView = bodyLabel
        self.iconView = iconImageView
        self.mediaView = contentMediaView
        self.callToActionView = actionButton
    }

    private func layoutSubviewsInLandscapeFormat(size: CGSize) {
        guard let nativeAd else { return }

        // Lay out the ad view on the right hand side
        let aspectRatio = nativeAd.mediaContent.aspectRatio
        let mediaHeight = size.height - (padding * 2.0)
        let mediaWidth = mediaHeight * aspectRatio
        contentMediaContainerView.frame.size = CGSize(width: mediaWidth, height: mediaHeight)
        contentMediaContainerView.frame.origin = CGPoint(x: (size.width - (googleButtonWidth + padding)) - mediaWidth,
                                                         y: padding)
        contentMediaView.frame = contentMediaContainerView.bounds
        contentMediaContainerView.layer.cornerRadius = 15.0

        // With the media view laid out, work out the remaning space we have
        let mediaTotalWidth = (mediaWidth + googleButtonWidth + padding + innerMargin)
        let textContentSize = CGSize(width: size.width - mediaTotalWidth,
                                     height: size.height)

        // Layout the icon if it is available
        iconImageView.isHidden = iconImageView.image == nil
        if !iconImageView.isHidden, let icon = nativeAd.icon?.image {
            let aspectRatio = icon.size.width / icon.size.height
            let iconSize = CGSize(width: iconHeight * aspectRatio, height: iconHeight)
            let iconOrigin = CGPoint(x: (textContentSize.width - iconSize.width) * 0.5, y: padding)
            iconImageView.frame = CGRect(origin: iconOrigin, size: iconSize)
            iconImageView.layer.cornerRadius = iconSize.height * 0.23
        }

        // Layout the action button at the bottom
        if !(actionButton.title(for: .normal)?.isEmpty ?? true) {
            actionButton.backgroundColor = self.tintColor
            let buttonSize = CGSize(width: textContentSize.width, height: ctaButtonHeight)
            let buttonOrigin = CGPoint(x: padding, y: size.height - (ctaButtonHeight + padding))
            actionButton.frame = CGRect(origin: buttonOrigin, size: buttonSize)
            actionButton.layer.cornerRadius = 15
            addSubview(actionButton)
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
        headlineLabel.textAlignment = .center
        headlineLabel.frame.size = headlineLabel.sizeThatFits(remainingTextSize)
        headlineLabel.frame.origin = CGPoint(x: (remainingTextSize.width - headlineLabel.frame.width) * 0.5,
                                             y: iconOriginY)

        // We're done if the label is hidden
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

    private func layoutSubviewsInPortraitFormat(size: CGSize) {
        guard let nativeAd else { return }

        var origin = CGPoint(x: padding, y: padding)

        // Lay out the icon view
        var iconSize = CGSize.zero
        iconImageView.isHidden = iconImageView.image == nil
        if !iconImageView.isHidden, let icon = nativeAd.icon?.image {
            let aspectRatio = icon.size.width / icon.size.height
            iconSize = CGSize(width: iconHeight * aspectRatio, height: iconHeight)
            iconImageView.frame = CGRect(origin: origin, size: iconSize)
            iconImageView.layer.cornerRadius = iconSize.height * 0.23
        }

        // Hide the body if we don't have any text
        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true

        // Position the title text
        let textX = iconImageView.isHidden ? padding : iconSize.width + innerMargin
        let textWidth = size.width - (textX + googleButtonWidth + (padding * 2.0) + (needsCompactLayout ? compactActionSize.width : 0.0))
        let textFittingSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

        headlineLabel.textAlignment = .left
        headlineLabel.frame.size = headlineLabel.sizeThatFits(textFittingSize)
        bodyLabel.frame.size = bodyLabel.isHidden ? .zero : bodyLabel.sizeThatFits(textFittingSize)
        let totalTextHeight = headlineLabel.frame.height + titleVerticalSpacing + bodyLabel.frame.height

        let textY = totalTextHeight < iconSize.height ? (iconSize.height - totalTextHeight) / 2.0 : padding
        headlineLabel.frame.origin = CGPoint(x: textX, y: textY)

        // Position the body text
        if !bodyLabel.isHidden {
            addSubview(bodyLabel)
            let textY = headlineLabel.frame.maxY + titleVerticalSpacing
            bodyLabel.frame.origin = CGPoint(x: textX, y: textY)
            bodyLabel.textAlignment = .left
        } else {
            bodyLabel.removeFromSuperview()
        }

        origin.y = max(iconImageView.frame.maxY, max(headlineLabel.frame.maxY, bodyLabel.frame.maxY)) + innerMargin

        if !(actionButton.title(for: .normal)?.isEmpty ?? true) {
            actionButton.backgroundColor = self.tintColor
            if !needsCompactLayout {
                let buttonSize = CGSize(width: size.width, height: ctaButtonHeight)
                let buttonOrigin = CGPoint(x: padding, y: size.height - ctaButtonHeight)
                actionButton.frame = CGRect(origin: buttonOrigin, size: buttonSize)
                actionButton.layer.cornerRadius = 15
            } else {
                actionButton.frame.size = compactActionSize
                actionButton.frame.origin = CGPoint(x: size.width - (actionButton.frame.width + padding),
                                                    y: max(headlineLabel.frame.minY + ((totalTextHeight - compactActionSize.height) / 2.0),
                                                           padding + googleButtonWidth + titleVerticalSpacing))
                actionButton.layer.cornerRadius = compactActionSize.height / 2.0
            }
        } else {
            actionButton.removeFromSuperview()
        }

        // Position the media container
        let mediaContent = nativeAd.mediaContent
        let aspectRatio = mediaContent.aspectRatio > 0.0 ? mediaContent.aspectRatio : 1.0
        let actionButtonY = (actionButton.superview != nil && !needsCompactLayout) ? (actionButton.frame.minY - innerMargin) : size.height
        let mediaContainerSize = CGSize(width: size.width, height: actionButtonY - origin.y)
        contentMediaContainerView.frame.size = mediaContainerSize
        contentMediaContainerView.frame.origin = CGPoint(x: padding, y: origin.y)
        contentMediaContainerView.layer.cornerRadius = 15.0
        updateMediaViewBackgroundColor()

        // Fit the media inside the container
        let isLandscape = aspectRatio > 1.0
        let mediaSize = CGSize(width: size.width, height: size.width / aspectRatio)
        let scale = min(mediaContainerSize.width / mediaSize.width,
                        mediaContainerSize.height / mediaSize.height)
        contentMediaView.frame.size = CGSize(width: isLandscape ? mediaContainerSize.width : mediaSize.width * scale,
                                             height: !isLandscape ? mediaContainerSize.height :mediaSize.height * scale)
        contentMediaView.frame.origin = CGPoint(x: (mediaContainerSize.width - contentMediaView.frame.width) * 0.5,
                                                y: (mediaContainerSize.height - contentMediaView.frame.height) * 0.5)

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
    private var maximumWidth: CGFloat { 500 }
    private var minimumWidth: CGFloat { 340 }
    private var maximumHeight: CGFloat { 750 }
    private var padding: CGFloat { 1.0 }
    private var outerMargin: CGFloat { frame.width < 375 ? 8.0 : 16.0 }
    private var innerMargin: CGFloat { 12.0 }
    private var titleVerticalSpacing: CGFloat { 1.0 }
    private var ctaButtonHeight: CGFloat { 54 }
    private var googleButtonWidth: CGFloat { 20.0 }
    private var displayScale: CGFloat { max(2.0, traitCollection.displayScale) }
    private var iconHeight: CGFloat { 64.0 }
    private var compactActionSize: CGSize { CGSize(width: 120, height: 40) }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let nativeAd else { return .zero }

        didSizeToAdContent = true

        // Aspect ratio of the ad view
        let aspectRatio = nativeAd.mediaContent.aspectRatio

        // Work out the horizontal width we can support
        // Cap it to the readable content width if applicable
        let width = min(size.width - (padding * 2.0), maximumWidth)

        // When in compact landscape, and a portrait ad, let's
        // line both up horizontally
        let isHorizontalLayout = (aspectRatio < 1.0) && needsCompactLayout
        if isHorizontalLayout {
            let height = size.height
            let mediaWidth = (height * aspectRatio) + innerMargin
            let adjustedWidth = min(size.width - (padding * 2.0), maximumWidth + mediaWidth)
            return CGSize(width: adjustedWidth, height: height)
        }

        // Line out the elements vertically
        var iconSize = CGSize.zero
        if let icon = nativeAd.icon?.image {
            let aspectRatio = icon.size.width / icon.size.height
            iconSize = CGSize(width: iconHeight * aspectRatio, height: iconHeight)
        }
        var textWidth = width - ((iconSize.width > 0.0 ? innerMargin + iconSize.width : 0.0) + googleButtonWidth)
        if needsCompactLayout { textWidth -= (innerMargin + compactActionSize.width) }
        let textSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

        // Start assembling the height off the size of the views
        var height: CGFloat = padding * 2.0

        // Add the size of the media content
        height += floor(width / aspectRatio)

        // Work out if the text or the icon is taller
        var textHeight = 0.0

        // Add the size of the title text
        headlineLabel.text = headlineText
        textHeight += headlineLabel.sizeThatFits(textSize).height

        // Add the subtitle text
        if let body = bodyText {
            textHeight += titleVerticalSpacing
            bodyLabel.text = body
            textHeight += bodyLabel.sizeThatFits(textSize).height
        }
        height += max(textHeight, iconSize.height) + innerMargin

        // Add the CTA button height
        if !needsCompactLayout {
            height += innerMargin + ctaButtonHeight
        }

        // Cap the height of the size to max supported
        let maxHeight = min(maximumHeight, size.height - (padding * 2.0))
        height = min(maxHeight, height)

        return CGSize(width: width, height: height)
    }
}

final public class PromoNativeAdContentView: PromoContentView {
    
    /// The ad model object that is being displayed
    public var nativeAd: GADNativeAd? {
        set { adView.nativeAd = newValue }
        get { adView.nativeAd }
    }

    public var mediaBackgroundImage: UIImage? {
        set { adView.mediaBackgroundImage = newValue }
        get { adView.mediaBackgroundImage }
    }

    // The hosted native ad view
    private let adView = PromoNativeAdView()

    required init(promoView: PromoView) {
        super.init(promoView: promoView)
        addSubview(adView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
 
    public override func layoutSubviews() {
        super.layoutSubviews()
        adView.frame = bounds
        adView.backgroundColor = promoView?.backgroundView.backgroundColor
    }

    override func prepareForReuse() {
        self.nativeAd = nil
        adView.reset()
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        adView.sizeThatFits(size)
    }
}
