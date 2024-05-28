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

    // Main, bold headline title shown at the top
    private let headlineLabel = UILabel()

    // Any auxiliary body text
    private let bodyLabel = UILabel()

    // A large call-to-action button shown at the bottom
    private let actionButton = UIButton(type: .system)

    // An icon image view optionally shown next to the headline
    private let iconImageView = UIImageView()

    // If media, the content view used to show the media
    private let contentMediaView = GADMediaView()

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

        contentMediaView.isUserInteractionEnabled = true
        contentMediaView.backgroundColor = UIColor(white: 1.0, alpha: 0.5)
        contentMediaView.clipsToBounds = true
        contentMediaView.frame.size = CGSize(width: 120, height: 120)
        if #available(iOS 13.0, *) {
            contentMediaView.layer.cornerCurve = .continuous
        }
        addSubview(contentMediaView)

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

        contentMediaView.mediaContent = nativeAd?.mediaContent

        actionButton.setTitle(nil, for: .normal)
        if let cta = nativeAd?.callToAction {
            actionButton.setTitle(cta.capitalized, for: .normal)
        }

        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard let nativeAd else { return }

        let size = frame.insetBy(dx: padding, dy: padding).size
        var origin = CGPoint(x: padding, y: padding)

        // Lay out the icon view
        var iconSize = CGSize.zero
        iconImageView.isHidden = iconImageView.image == nil
        if !iconImageView.isHidden {
            iconSize = self.iconSize
            iconImageView.frame = CGRect(origin: origin, size: iconSize)
            iconImageView.layer.cornerRadius = iconSize.width * 0.23
        }

        // Hide the body if we don't have any text
        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true

        // Position the title text
        let textX = iconImageView.isHidden ? padding : iconSize.width + innerMargin
        let textWidth = size.width - (textX + googleButtonWidth + (padding * 2.0) + (needsCompactLayout ? compactActionSize.width : 0.0))
        let textFittingSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

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
        } else {
            bodyLabel.removeFromSuperview()
        }

        origin.y = max(iconImageView.frame.maxY, max(headlineLabel.frame.maxY, bodyLabel.frame.maxY)) + innerMargin

        // Position the media
        let mediaContent = nativeAd.mediaContent
        let aspectRatio = mediaContent.aspectRatio > 0.0 ? mediaContent.aspectRatio : 1.0
        let mediaSize = CGSize(width: size.width, height: min(floor(size.width / aspectRatio), size.height - origin.y))
        contentMediaView.frame.size = mediaSize
        contentMediaView.frame.origin = CGPoint(x: padding, y: origin.y)
        contentMediaView.layer.cornerRadius = 15.0
        updateMediaViewBackgroundColor()

        if !(actionButton.title(for: .normal)?.isEmpty ?? true) {
            actionButton.backgroundColor = self.tintColor
            if !needsCompactLayout {
                let buttonSize = CGSize(width: size.width, height: ctaButtonHeight)
                let buttonOrigin = CGPoint(x: padding, y: size.height - ctaButtonHeight)
                actionButton.frame = CGRect(origin: buttonOrigin, size: buttonSize)
                actionButton.layer.cornerRadius = 15
            } else {
                actionButton.frame.size = compactActionSize
                actionButton.frame.origin = CGPoint(x: size.width - actionButton.frame.width, y: headlineLabel.frame.minY + ((totalTextHeight - compactActionSize.height) / 2.0))
                actionButton.layer.cornerRadius = compactActionSize.height / 2.0
            }
        } else {
            actionButton.removeFromSuperview()
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

    private func updateMediaViewBackgroundColor() {
        var h: CGFloat = 0, s: CGFloat = 0
        var b: CGFloat = 0, a: CGFloat = 0

        var color: UIColor? = backgroundColor
        if #available(iOS 13.0, *) {
            color = backgroundColor?.resolvedColor(with: traitCollection)
        }

        guard let color, color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return }

        contentMediaView.backgroundColor = UIColor(hue: h,
                                                   saturation: max(s - 0.1, 0.0),
                                                   brightness: min(b + 0.05, 1.0),
                                                   alpha: a)
    }

    // MARK: - Sizing

    // Static sizing values
    private var needsCompactLayout: Bool { traitCollection.verticalSizeClass == .compact }
    private var maximumWidth: CGFloat { 550 }
    private var minimumWidth: CGFloat { 300 }
    private var maximumHeight: CGFloat { 700 }
    private var padding: CGFloat { 1.0 }
    private var outerMargin: CGFloat { frame.width < 375 ? 8.0 : 16.0 }
    private var innerMargin: CGFloat { needsCompactLayout ? 8.0 : 12.0 }
    private var titleVerticalSpacing: CGFloat { 1.0 }
    private var ctaButtonHeight: CGFloat { 54 }
    private var googleButtonWidth: CGFloat { 20.0 }
    private var displayScale: CGFloat { max(2.0, traitCollection.displayScale) }
    private var iconSize: CGSize { CGSize(width: 64, height: 64) }
    private var compactActionSize: CGSize { CGSize(width: 90, height: 36) }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let nativeAd else { return .zero }

        // Work out the horizontal width we can support
        // Cap it to the readable content width if applicable
        let aspectRatio = nativeAd.mediaContent.aspectRatio
        let width = preferredWidth(in: size, aspectRatio: aspectRatio)
        var iconSize = CGSize.zero
        if nativeAd.icon?.image != nil {
            iconSize = self.iconSize
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

        return CGSize(width: width, height: height)
    }

    private func minimumHeight() -> CGFloat {
        // Work out the minimum height we can possibly fit without the media
        var height = 0.0
        height += headlineLabel.font.lineHeight * 2.0
        height += titleVerticalSpacing
        height += bodyLabel.font.lineHeight * 3.0
        height += innerMargin
        if !needsCompactLayout {
            height += ctaButtonHeight
        }
        return height
    }

    // Given the aspect ratio of the media, and the hypothetical overall height of the other elements,
    // work out what the proper width should be to fit everything on screen
    private func preferredWidth(in size: CGSize, aspectRatio: CGFloat) -> CGFloat {
        // Total width available to us
        let width = min(size.width - (padding * 2.0), maximumWidth)
        let height = min(size.height, maximumHeight)

        // Sans the media, how much height we're guaranteed to take up
        let minimumHeight = minimumHeight()

        // Work out how big the view would be with the media aligned to the width

        let mediaHeight = width / aspectRatio

        // If it's not too tall to fit into our bounds
        if minimumHeight + mediaHeight < height {
            return width
        }

        let availableHeight = height - minimumHeight
        return availableHeight * aspectRatio
    }
}

final public class PromoNativeAdContentView: PromoContentView {
    
    /// The ad model object that is being displayed
    public var nativeAd: GADNativeAd? {
        set { adView.nativeAd = newValue }
        get { adView.nativeAd }
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
