import AppKit

/// Left gutter that prints each line's remaining-time stamp.
///
/// Living outside the text storage means the stamps cannot be edited away, and
/// changing the detail level is just a redraw.
final class StampRulerView: NSRulerView {
    weak var controller: NoteEditorController?

    private let horizontalPadding: CGFloat = 8
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        ruleThickness = 56
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateThickness(sample: String) {
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        let thickness = max(24, ceil(width) + horizontalPadding * 2)
        if abs(thickness - ruleThickness) > 0.5 {
            ruleThickness = thickness
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()

        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let controller,
              controller.paragraphCount > 0,
              let layoutManager = controller.textView.layoutManager,
              let textContainer = controller.textView.textContainer
        else { return }

        let textView = controller.textView
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let inset = textView.textContainerInset.height
        // Text view origin in gutter coordinates, which folds in the scroll offset.
        let originY = convert(NSPoint.zero, from: textView).y

        for index in controller.lineIndexRange(intersecting: characterRange) {
            let stamp = controller.stampText(forLine: index)
            guard !stamp.isEmpty else { continue }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: index == controller.caretLine
                    ? NSColor.secondaryLabelColor
                    : NSColor.tertiaryLabelColor
            ]
            let lineRect = controller.firstLineFragmentRect(forLine: index)
            let size = (stamp as NSString).size(withAttributes: attributes)
            let y = lineRect.minY + inset + originY + (lineRect.height - size.height) / 2
            let x = bounds.maxX - horizontalPadding - size.width

            guard y + size.height > rect.minY, y < rect.maxY else { continue }
            (stamp as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
    }
}
