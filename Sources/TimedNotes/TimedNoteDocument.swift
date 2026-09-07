import AppKit
import Combine
import SwiftUI
import TimedNotesCore
import TimedNotesEditor
import UniformTypeIdentifiers

extension UTType {
    /// Markdown inside, so any editor can read it; its own extension outside, so
    /// Timed Notes does not claim every text file on the disk.
    static let timedNote = UTType(exportedAs: "com.kharkion.timednotes.note", conformingTo: .plainText)
}

/// One note, one timer, one window.
@MainActor
final class TimedNoteDocument: @preconcurrency ReferenceFileDocument {
    typealias Snapshot = NoteSnapshot

    static var readableContentTypes: [UTType] { [.timedNote, .plainText] }
    static var writableContentTypes: [UTType] { [.timedNote] }

    let timer = TimerEngine()
    let editor = NoteEditorController()

    /// Bumped on every change so SwiftUI knows the document needs saving.
    @Published private(set) var revision = 0

    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingFile = false

    init() {
        configure()
    }

    required init(configuration: ReadConfiguration) throws {
        configure()

        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }

        apply(MarkdownNote.snapshot(from: text))
    }

    func snapshot(contentType: UTType) throws -> NoteSnapshot {
        currentSnapshot()
    }

    func fileWrapper(snapshot: NoteSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(MarkdownNote.text(for: snapshot).utf8))
    }

    // MARK: - Output

    /// Copies the selected lines with their stamps, or the whole note when
    /// nothing is selected.
    func copyWithStamps() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(editor.stampedText(selectionOnly: true), forType: .string)
    }

    func exportToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "timed-note.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? editor.stampedText(selectionOnly: false).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Internals

    private func configure() {
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
    }

    private func apply(_ snapshot: NoteSnapshot) {
        isApplyingFile = true
        editor.format = snapshot.format
        timer.restore(duration: snapshot.duration, heldRemaining: snapshot.heldRemaining)
        editor.load(lines: snapshot.lines)
        isApplyingFile = false
    }

    private func currentSnapshot() -> NoteSnapshot {
        NoteSnapshot(
            duration: timer.duration,
            heldRemaining: timer.exactRemaining,
            format: editor.format,
            lines: editor.lines()
        )
    }

    /// Opening a file is not an edit, or every note would open pre-dirtied.
    private func markChanged() {
        guard !isApplyingFile else { return }
        revision &+= 1
    }
}
