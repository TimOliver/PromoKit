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

    // If no media, the image view shown in place
    private let contentImageView = UIImageView()

    // If media, the content view used to show the media
    private let contentMediaView = GADMediaView()

    public init() {
        super.init(frame: .zero)
        configureContentViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContentViews() {
        self.headlineView = headlineLabel
        let headlineFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        headlineLabel.font = UIFontMetrics.default.scaledFont(for: headlineFont)
        headlineLabel.numberOfLines = 0
        addSubview(headlineLabel)

        self.bodyView = bodyLabel
        let bodyFont = UIFont.systemFont(ofSize: 18.0)
        bodyLabel.font = UIFontMetrics.default.scaledFont(for: bodyFont)
        bodyLabel.numberOfLines = 0
        addSubview(bodyLabel)

        self.iconView = iconImageView
        iconImageView.clipsToBounds = true
        if #available(iOS 13.0, *) {
            iconImageView.layer.cornerCurve = .continuous
        }
        addSubview(iconImageView)

        self.mediaView = contentMediaView
        contentMediaView.isUserInteractionEnabled = true
        contentMediaView.backgroundColor = UIColor(white: 1.0, alpha: 0.5)
        contentMediaView.clipsToBounds = true
        if #available(iOS 13.0, *) {
            contentMediaView.layer.cornerCurve = .continuous
        }
        addSubview(contentMediaView)

        self.callToActionView = actionButton
        actionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18.0)
        actionButton.backgroundColor = .red
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.isUserInteractionEnabled = false
        actionButton.clipsToBounds = true
        if #available(iOS 13.0, *) {
            actionButton.layer.cornerCurve = .continuous
        }
        addSubview(actionButton)
    }

    private func updateAdContent() {
        iconImageView.image = nativeAd?.icon?.image
        headlineLabel.text = nativeAd?.headline
        bodyLabel.text = nativeAd?.body

        contentMediaView.mediaContent = nativeAd?.mediaContent

        contentImageView.image = nil
        if let nativeImage = nativeAd?.images?.first, nativeImage.image != nil {
            contentImageView.image = nativeImage.image
        }

        actionButton.setTitle(nil, for: .normal)
        if let cta = nativeAd?.callToAction {
            actionButton.setTitle(cta.capitalized, for: .normal)
        }

        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        
        let size = frame.size
        var origin = CGPoint(x: 0, y: 0)

        // Lay out the icon view
        var iconSize = CGSize.zero
        iconImageView.isHidden = iconImageView.image == nil
        if !iconImageView.isHidden {
            iconSize = self.iconSize
            iconImageView.frame = CGRect(origin: origin, size: iconSize)
            iconImageView.layer.cornerRadius = 15
        }

        // Hide the body if we don't have any text
        bodyLabel.isHidden = bodyLabel.text?.isEmpty ?? true

        // Position the title text
        let textX = iconImageView.isHidden ? 0.0 : iconSize.width + (innerMargin)
        let textWidth = size.width - textX - googleButtonWidth
        let textFittingSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)

        headlineLabel.frame.size = headlineLabel.sizeThatFits(textFittingSize)
        let textY = bodyLabel.isHidden ?
                        (iconSize.height / 2.0) - (headlineLabel.bounds.midY)
                    : 0.0
        headlineLabel.frame.origin = CGPoint(x: textX, y: textY)

        // Position the body text
        if !bodyLabel.isHidden {
            addSubview(bodyLabel)
            let textY = headlineLabel.frame.maxY + titleVerticalSpacing
            bodyLabel.frame.size = bodyLabel.sizeThatFits(textFittingSize)
            bodyLabel.frame.origin = CGPoint(x: textX, y: textY)
        } else {
            bodyLabel.frame = .zero
            bodyLabel.removeFromSuperview()
        }

        origin.y = max(iconImageView.frame.maxY, bodyLabel.frame.maxY) + innerMargin

        // Position the media
        if let mediaContent = nativeAd?.mediaContent {
            let mediaSize = CGSize(width: size.width, height: size.width / mediaContent.aspectRatio)
            contentMediaView.frame.size = mediaSize
            contentMediaView.frame.origin = CGPoint(x: 0.0, y: origin.y)
            contentMediaView.layer.cornerRadius = 10.0
        }

        if !(actionButton.title(for: .normal)?.isEmpty ?? true) {
            let buttonSize = CGSize(width: size.width, height: ctaButtonHeight)
            let buttonOrigin = CGPoint(x: 0, y: size.height - ctaButtonHeight)
            actionButton.frame = CGRect(origin: buttonOrigin, size: buttonSize)
            actionButton.layer.cornerRadius = 15
        }
    }

    // MARK: - Sizing

    // Static sizing values
    private var maximumWidth: CGFloat { 620 }
    private var minimumWidth: CGFloat { 300 }
    private var iconSize: CGSize { CGSize(width: 64, height: 64) }
    private var outerMargin: CGFloat { frame.width < 375 ? 8.0 : 16.0 }
    private var innerMargin: CGFloat { 16.0 }
    private var titleVerticalSpacing: CGFloat { 6.0 }
    private var ctaButtonHeight: CGFloat { 54 }
    private var googleButtonWidth: CGFloat { 20.0 }
    private var displayScale: CGFloat { max(2.0, traitCollection.displayScale) }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let nativeAd else { return .zero }

        // Work out the horizontal width we can support
        // Cap it to the readable content width if applicable
        let width = min(size.width, maximumWidth)
        var iconSize = CGSize.zero
        if nativeAd.icon?.image != nil {
            iconSize = self.iconSize
        }
        let textWidth = width - ((iconSize.width > 0.0 ? innerMargin + iconSize.width : 0.0) + googleButtonWidth)

        // Start assembling the height off the size of the views
        var height: CGFloat = 0.0

        // Add the size of the media content
        height += floor(width / nativeAd.mediaContent.aspectRatio)

        // Work out if the text or the icon is taller
        var textHeight = 0.0

        // Add the size of the title text
        if let headline = nativeAd.headline {
            textHeight += heightOfString(headline, width: textWidth, font: headlineLabel.font)
        }

        // Add the subtitle text
        if let body = nativeAd.body {
            textHeight += titleVerticalSpacing
            textHeight += heightOfString(body, width: textWidth, font: bodyLabel.font)
        }
        height += max(textHeight, iconSize.height) + innerMargin

        // Add the CTA button height
        height += innerMargin + ctaButtonHeight

        return CGSize(width: width, height: height)
    }

    private func heightOfString(_ string: String, width: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = string.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
        return ceil(boundingBox.height)
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
    }

    override func prepareForReuse() {
        self.nativeAd = nil
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        adView.sizeThatFits(size)
    }
}
