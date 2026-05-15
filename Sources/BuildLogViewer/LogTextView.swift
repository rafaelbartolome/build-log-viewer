import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    let text: String
    let lineNumbers: [Int]
    let lineStartOffsets: [Int]
    let highlightedRanges: [NSRange]
    let navigationRange: NSRange?
    let navigationToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LogTextContainerView {
        let containerView = LogTextContainerView()
        let scrollView = containerView.scrollView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView

        containerView.gutterView.textView = textView

        context.coordinator.textView = textView
        context.coordinator.gutterView = containerView.gutterView
        context.coordinator.observeBoundsChanges(of: scrollView.contentView)
        return containerView
    }

    func updateNSView(_ containerView: LogTextContainerView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        if context.coordinator.loadedText != text {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.coordinator.loadedText = text
            context.coordinator.lastNavigationToken = nil
        }

        context.coordinator.gutterView?.update(lineNumbers: lineNumbers, lineStartOffsets: lineStartOffsets)
        applyHighlights(to: textView)

        if context.coordinator.lastNavigationToken != navigationToken {
            context.coordinator.lastNavigationToken = navigationToken
            if let navigationRange {
                let clamped = clampedRange(navigationRange, textLength: (textView.string as NSString).length)
                textView.setSelectedRange(clamped)
                textView.scrollRangeToVisible(clamped)
            }
        }

        _ = containerView
    }

    private func applyHighlights(to textView: NSTextView) {
        let textLength = (textView.string as NSString).length
        guard textLength > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: textLength)
        textView.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.35)
        for range in highlightedRanges {
            let clamped = clampedRange(range, textLength: textLength)
            guard clamped.length > 0 else {
                continue
            }
            textView.layoutManager?.addTemporaryAttribute(.backgroundColor, value: highlightColor, forCharacterRange: clamped)
        }
    }

    private func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
        guard textLength > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let location = min(max(0, range.location), textLength - 1)
        let maxLength = textLength - location
        return NSRange(location: location, length: min(max(range.length, 0), maxLength))
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var textView: NSTextView?
        weak var gutterView: LineNumberGutterView?
        var loadedText = ""
        var lastNavigationToken: UUID?

        func observeBoundsChanges(of clipView: NSClipView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        @objc private func clipViewBoundsDidChange(_ notification: Notification) {
            gutterView?.needsDisplay = true
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

final class LogTextContainerView: NSView {
    let gutterView = LineNumberGutterView()
    let scrollView = NSScrollView()

    private var gutterWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true

        gutterView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gutterView)
        addSubview(scrollView)

        let gutterWidthConstraint = gutterView.widthAnchor.constraint(equalToConstant: gutterView.preferredWidth)
        self.gutterWidthConstraint = gutterWidthConstraint

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidthConstraint,
            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        gutterView.onPreferredWidthChange = { [weak self] width in
            self?.gutterWidthConstraint?.constant = width
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    private var lineNumbers: [Int] = []
    private var lineStartOffsets: [Int] = []
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let horizontalPadding: CGFloat = 8
    var onPreferredWidthChange: ((CGFloat) -> Void)?
    private(set) var preferredWidth: CGFloat = 58

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        needsDisplay = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(lineNumbers: [Int], lineStartOffsets: [Int]) {
        self.lineNumbers = lineNumbers
        self.lineStartOffsets = lineStartOffsets
        updateThickness()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] lineRect, _, _, glyphRange, _ in
            guard let self,
                  glyphRange.location < layoutManager.numberOfGlyphs else {
                return
            }

            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            let lineIndex = self.lineIndex(containingUTF16Offset: characterIndex)
            guard self.lineNumbers.indices.contains(lineIndex) else {
                return
            }

            let label = "\(self.lineNumbers[lineIndex])" as NSString
            let labelSize = label.size(withAttributes: attributes)
            let textPoint = NSPoint(
                x: 0,
                y: lineRect.minY + textView.textContainerOrigin.y
            )
            let gutterPoint = self.convert(textPoint, from: textView)
            let drawRect = NSRect(
                x: self.bounds.minX + self.horizontalPadding,
                y: gutterPoint.y,
                width: self.bounds.width - (self.horizontalPadding * 2),
                height: labelSize.height
            )

            label.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes
            )
        }
    }

    private func updateThickness() {
        let maxLineNumber = lineNumbers.last ?? 1
        let digits = max(3, String(maxLineNumber).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: labelFont]).width + (horizontalPadding * 2) + 4
        let newPreferredWidth = max(44, ceil(width))
        if newPreferredWidth != preferredWidth {
            preferredWidth = newPreferredWidth
            onPreferredWidthChange?(newPreferredWidth)
        }
    }

    private func lineIndex(containingUTF16Offset offset: Int) -> Int {
        guard !lineStartOffsets.isEmpty else {
            return 0
        }

        var lowerBound = 0
        var upperBound = lineStartOffsets.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if lineStartOffsets[midpoint] <= offset {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return max(0, lowerBound - 1)
    }
}
