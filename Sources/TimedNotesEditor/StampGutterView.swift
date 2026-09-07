import AppKit
import TimedNotesCore

/// Left gutter that prints each line's stamp.
///
/// A plain sibling view, not an `NSRulerView`: the ruler tiling machinery fights
/// with SwiftUI's sizing of the scroll view and ends up offsetting the clip view
/// so that the text is never shown.
final class StampGutterView: NSView {
    weak var controller: NoteEditorController?

    private(set) var preferredWidth: CGFloat = 56
    private let horizontalPadding: CGFloat = 8
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// Flipped to share the text view's top-down coordinates.
    override var isFlipped: Bool { true }

    /// Sized to the widest stamp the current format can produce.
    func updateWidth(sample: String) -> Bool {
        guard !sample.isEmpty else {
            let changed = preferredWidth != 0
            preferredWidth = 0
            return changed
        }

        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        let candidate = max(24, ceil(width) + horizontalPadding * 2)
        guard abs(candidate - preferredWidth) > 0.5 else { return false }
        preferredWidth = candidate
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard bounds.width > 1 else { return }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        guard let controller,
              let layoutManager = controller.textView.layoutManager,
              let container = controller.textView.textContainer
        else { return }

        let textView = controller.textView
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let inset = textView.textContainerInset.height

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
            // Scrolling the text moves the stamps with it.
            let y = lineRect.minY + inset - visibleRect.origin.y + (lineRect.height - size.height) / 2
            let x = bounds.maxX - horizontalPadding - size.width

            guard y + size.height > dirtyRect.minY, y < dirtyRect.maxY else { continue }
            (stamp as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
    }
}

/// Lays the gutter out beside the text, replacing the scroll view's ruler.
final class NoteEditorContainerView: NSView {
    let gutter: StampGutterView
    let scrollView: NSScrollView

    init(gutter: StampGutterView, scrollView: NSScrollView) {
        self.gutter = gutter
        self.scrollView = scrollView
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        addSubview(gutter)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let width = min(gutter.preferredWidth, max(0, bounds.width / 3))
        gutter.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        scrollView.frame = NSRect(x: width, y: 0, width: bounds.width - width, height: bounds.height)
    }
}
