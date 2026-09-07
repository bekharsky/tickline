import AppKit
import Combine
import SwiftUI
import TimedNotesCore
import TimedNotesEditor
import UniformTypeIdentifiers

extension UTType {
    /// Older notes used a private `.timednote` extension. The bytes are still
    /// Markdown; this type only exists so Finder can hand those files back.
    static let legacyTimedNote = UTType(importedAs: "com.kharion.tickline.legacy-note")
}

/// One note, one timer, one window.
///
/// AppKit builds documents on a background queue whenever a file is opened from
/// a URL, so this half holds nothing but the bytes that were read. The timer and
/// the editor are AppKit objects and only come to life in `session`, on the main
/// thread, when a window finally asks for them.
final class TimedNoteDocument: ReferenceFileDocument {
    typealias Snapshot = NoteSnapshot

    /// Save as ordinary Markdown. The timer and stamps live in the text, so
    /// the filename does not have to advertise the format.
    static var readableContentTypes: [UTType] {
        [Self.markdownType, .plainText, .legacyTimedNote]
    }
    static var writableContentTypes: [UTType] { [Self.markdownType] }

    /// `UTType.markdown` is not always in the SDK this package builds against.
    /// The filename tag is enough: `.md` is Markdown everywhere that matters.
    private static let markdownType = UTType(filenameExtension: "md") ?? .plainText

    /// Bumped on every change so SwiftUI knows the document needs saving.
    @Published private(set) var revision = 0

    private let loaded: NoteSnapshot?
    private var live: NoteSession?

    init() {
        loaded = nil
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }

        loaded = MarkdownNote.snapshot(from: text)
    }

    @MainActor var timer: TimerEngine { session.timer }
    @MainActor var editor: NoteEditorController { session.editor }

    @MainActor var session: NoteSession {
        if let live { return live }
        let session = NoteSession(loaded: loaded) { [weak self] in self?.revision &+= 1 }
        live = session
        return session
    }

    func snapshot(contentType: UTType) throws -> NoteSnapshot {
        onMain { $0.currentSnapshot() }
    }

    func fileWrapper(snapshot: NoteSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(MarkdownNote.text(for: snapshot).utf8))
    }

    // MARK: - Output

    /// Copies the selected lines with their stamps, or the whole note when
    /// nothing is selected.
    @MainActor
    func copyWithStamps() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(editor.stampedText(selectionOnly: true), forType: .string)
    }

    @MainActor
    func exportToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tickline.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? editor.stampedText(selectionOnly: false).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Saving may be driven from a background queue, while the state being saved
    /// lives in AppKit views. A synchronous hop is safe here: the main thread is
    /// never the one waiting for the save to finish.
    private func onMain<T>(_ body: @MainActor (NoteSession) -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body(session) }
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { body(self.session) } }
    }
}

/// The living note: the timer, the editor, and the wiring that marks the
/// document dirty when either of them moves.
@MainActor
final class NoteSession {
    let timer = TimerEngine()
    let editor = NoteEditorController()

    private let changed: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingFile = false

    init(loaded: NoteSnapshot?, changed: @escaping () -> Void) {
        self.changed = changed

        editor.timer = timer
        editor.onChange = { [weak self] in self?.markChanged() }

        timer.$phase
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] phase in
                if phase == .overtime {
                    NSSound.beep()
                }
                self?.editor.refreshGutter(resize: false)
                self?.markChanged()
            }
            .store(in: &cancellables)

        timer.$duration
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.editor.refreshGutter(resize: true)
                self?.markChanged()
            }
            .store(in: &cancellables)

        editor.$format
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.markChanged() }
            .store(in: &cancellables)

        if let loaded {
            apply(loaded)
        }
    }

    func currentSnapshot() -> NoteSnapshot {
        NoteSnapshot(
            duration: timer.duration,
            heldRemaining: timer.exactRemaining,
            format: editor.format,
            lines: editor.lines()
        )
    }

    private func apply(_ snapshot: NoteSnapshot) {
        isApplyingFile = true
        editor.format = snapshot.format
        timer.restore(duration: snapshot.duration, heldRemaining: snapshot.heldRemaining)
        editor.load(lines: snapshot.lines)
        isApplyingFile = false
    }

    /// Opening a file is not an edit, or every note would open pre-dirtied.
    private func markChanged() {
        guard !isApplyingFile else { return }
        changed()
    }
}
