import AppKit
import Combine
import TimedNotesCore

/// Owns the TextKit stack and drives `StampBookkeeper` from the text view.
///
/// The note text stays plain: stamps live beside it and are drawn in the gutter.
/// That is what makes the detail level reversible — nothing about a line is lost
/// when hours or seconds are switched off.
@MainActor
public final class NoteEditorController: NSObject, ObservableObject, NSTextViewDelegate {
    public let scrollView = NSScrollView()
    public let textView: NSTextView

    @Published public var format: StampFormat = .clock {
        didSet {
            guard format != oldValue else { return }
            refreshGutter(resize: true)
        }
    }

    @Published public private(set) var caretLine = 0
    @Published public private(set) var caretStamp: LineStamp?
    @Published public private(set) var lineCount = 1

    /// Called after every edit so the session can be autosaved.
    public var onChange: (() -> Void)?

    public weak var timer: TimerEngine? {
        didSet { refreshGutter(resize: true) }
    }

    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()
    let gutter: StampRulerView

    private var bookkeeper = StampBookkeeper()
    private var isLoading = false

    public override init() {
        textContainer.widthTracksTextView = true
        textContainer.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: textContainer)
        gutter = StampRulerView(scrollView: scrollView)

        super.init()

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 6, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = gutter
        scrollView.rulersVisible = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder

        gutter.controller = self
        gutter.clientView = textView

        // The gutter has to follow the text while scrolling.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        refreshGutter(resize: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: - Session

    public func lines() -> [NoteSnapshot.Line] {
        bookkeeper.lines(in: storage.string)
    }

    public func load(lines: [NoteSnapshot.Line]) {
        guard !lines.isEmpty else { return }

        isLoading = true
        textView.string = lines.map(\.text).joined(separator: "\n")
        bookkeeper.reset(lines: lines)
        isLoading = false

        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        refreshGutter(resize: true)
        updateCaretState()
    }

    public func stampedText() -> String {
        NoteExporter.plainText(lines: lines(), format: format)
    }

    public func refreshGutter(resize: Bool) {
        if resize {
            gutter.updateThickness(
                sample: StampFormatter.widestSample(duration: timer?.duration ?? 3600, format: format)
            )
        }
        gutter.needsDisplay = true
    }

    // MARK: - Gutter data

    var paragraphCount: Int { bookkeeper.lineCount }

    func stampText(forLine index: Int) -> String {
        guard !format.isEmpty else { return "" }
        guard let stamp = bookkeeper.stamp(forLine: index) else {
            return StampFormatter.placeholder(for: format)
        }
        return StampFormatter.string(for: stamp.remaining, format: format)
    }

    func lineIndexRange(intersecting characterRange: NSRange) -> Range<Int> {
        bookkeeper.paragraphs.indexRange(intersecting: characterRange)
    }

    /// Vertical position of a paragraph's first line fragment, in text view
    /// coordinates. A wrapped paragraph keeps one stamp, at its top.
    func firstLineFragmentRect(forLine index: Int) -> NSRect {
        let range = bookkeeper.paragraphs.range(forLine: index)
        let fallbackHeight = layoutManager.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: 14))

        if storage.length == 0 || range.location >= storage.length {
            let extra = layoutManager.extraLineFragmentRect
            if extra != .zero {
                return extra
            }
            if storage.length == 0 {
                return NSRect(x: 0, y: 0, width: 0, height: fallbackHeight)
            }
        }

        let characterIndex = min(range.location, max(0, storage.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return rect == .zero ? NSRect(x: 0, y: 0, width: 0, height: fallbackHeight) : rect
    }

    // MARK: - NSTextViewDelegate

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard !isLoading, let replacementString else { return true }

        bookkeeper.prepareEdit(
            currentText: storage.string,
            affectedRange: affectedCharRange,
            replacement: replacementString,
            stamp: timer?.currentStamp()
        )
        return true
    }

    public func textDidChange(_ notification: Notification) {
        guard !isLoading else { return }

        bookkeeper.commitEdit(newText: storage.string, stamp: timer?.currentStamp())
        refreshGutter(resize: false)
        updateCaretState()
        onChange?()
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoading else { return }
        updateCaretState()
        gutter.needsDisplay = true
    }

    // MARK: - Internals

    @objc private func contentBoundsDidChange() {
        gutter.needsDisplay = true
    }

    private func updateCaretState() {
        let index = bookkeeper.paragraphs.index(forCharacterAt: textView.selectedRange().location)
        caretLine = index
        caretStamp = bookkeeper.stamp(forLine: index)
        lineCount = bookkeeper.lineCount
    }
}
