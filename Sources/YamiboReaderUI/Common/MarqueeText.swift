import SwiftUI

#if os(iOS)
import UIKit

struct MarqueeText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .headline
    var spacing: CGFloat = 28
    var pointsPerSecond: CGFloat = 36

    static func preferredHeight(for textStyle: UIFont.TextStyle) -> CGFloat {
        ceil(UIFont.preferredFont(forTextStyle: textStyle).lineHeight)
    }

    func makeUIView(context: Context) -> MarqueeLabelView {
        let view = MarqueeLabelView()
        view.textColor = .label
        return view
    }

    func updateUIView(_ uiView: MarqueeLabelView, context: Context) {
        uiView.text = text
        uiView.textStyle = textStyle
        uiView.spacing = spacing
        uiView.pointsPerSecond = pointsPerSecond
        uiView.applyCurrentConfiguration()
    }
}

final class MarqueeLabelView: UIView {
    private let contentView = UIView()
    private let primaryLabel = UILabel()
    private let secondaryLabel = UILabel()

    var text: String = ""
    var textStyle: UIFont.TextStyle = .headline
    var textColor: UIColor = .label {
        didSet {
            primaryLabel.textColor = textColor
            secondaryLabel.textColor = textColor
        }
    }
    var spacing: CGFloat = 28
    var pointsPerSecond: CGFloat = 36

    private var lastAnimatedWidth: CGFloat = .zero
    private var lastBoundsSize: CGSize = .zero
    private var lastText: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true
        isUserInteractionEnabled = false

        primaryLabel.numberOfLines = 1
        secondaryLabel.numberOfLines = 1
        primaryLabel.lineBreakMode = .byClipping
        secondaryLabel.lineBreakMode = .byClipping
        primaryLabel.adjustsFontForContentSizeCategory = true
        secondaryLabel.adjustsFontForContentSizeCategory = true

        addSubview(contentView)
        contentView.addSubview(primaryLabel)
        contentView.addSubview(secondaryLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyCurrentConfiguration()
    }

    override var intrinsicContentSize: CGSize {
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(font.lineHeight))
    }

    func applyCurrentConfiguration() {
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        primaryLabel.font = font
        secondaryLabel.font = font
        primaryLabel.textColor = textColor
        secondaryLabel.textColor = textColor
        primaryLabel.text = text
        secondaryLabel.text = text

        invalidateIntrinsicContentSize()

        let boundsSize = bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        let measuredWidth = ceil(primaryLabel.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: boundsSize.height)).width)
        let needsAnimationReset =
            abs(measuredWidth - lastAnimatedWidth) > 0.5 ||
            boundsSize != lastBoundsSize ||
            text != lastText

        guard needsAnimationReset else { return }

        lastAnimatedWidth = measuredWidth
        lastBoundsSize = boundsSize
        lastText = text

        contentView.layer.removeAllAnimations()

        let labelHeight = ceil(font.lineHeight)
        let y = max(0, (boundsSize.height - labelHeight) / 2)

        if measuredWidth <= boundsSize.width {
            contentView.frame = bounds
            primaryLabel.frame = CGRect(x: 0, y: y, width: boundsSize.width, height: labelHeight)
            secondaryLabel.isHidden = true
            return
        }

        secondaryLabel.isHidden = false

        let travel = measuredWidth + spacing
        contentView.frame = CGRect(x: 0, y: 0, width: measuredWidth * 2 + spacing, height: boundsSize.height)
        primaryLabel.frame = CGRect(x: 0, y: y, width: measuredWidth, height: labelHeight)
        secondaryLabel.frame = CGRect(x: travel, y: y, width: measuredWidth, height: labelHeight)

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -travel
        animation.duration = CFTimeInterval(travel / max(pointsPerSecond, 1))
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        contentView.layer.add(animation, forKey: "marquee")
    }
}

#else

struct MarqueeText: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(1)
    }
}

#endif
