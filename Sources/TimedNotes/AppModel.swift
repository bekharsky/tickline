import AppKit
import Combine
import TimedNotesCore
import TimedNotesEditor

@MainActor
final class AppModel: ObservableObject {
    let timer = TimerEngine()
    let editor = NoteEditorController()

    @Published var isDurationEditorPresented = false

    private let store = SessionStore()
    private var saveWorkItem: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        editor.timer = timer
        editor.onChange = { [weak self] in self?.scheduleSave() }

        restore()

        timer.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                if phase == .overtime {
                    NSSound.beep()
                }
                self?.editor.refreshGutter(resize: false)
                self?.scheduleSave()
            }
            .store(in: &cancellables)

        timer.$duration
            .removeDuplicates()
            .sink { [weak self] _ in self?.editor.refreshGutter(resize: true) }
            .store(in: &cancellables)

        editor.$format
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleSave() }
            .store(in: &cancellables)
    }

    // MARK: - Session

    private func restore() {
        guard let snapshot = store.load() else { return }
        editor.format = snapshot.format
        timer.restore(duration: snapshot.duration, heldRemaining: snapshot.heldRemaining)
        editor.load(lines: snapshot.lines)
    }

    func snapshot() -> NoteSnapshot {
        NoteSnapshot(
            duration: timer.duration,
            heldRemaining: timer.exactRemaining,
            format: editor.format,
            lines: editor.lines()
        )
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        saveWorkItem = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        try? store.save(snapshot())
    }

    func startNewSession() {
        let alert = NSAlert()
        alert.messageText = "Start a new session?"
        alert.informativeText = "The current note and its timestamps will be cleared."
        alert.addButton(withTitle: "New session")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        timer.reset()
        editor.load(lines: [NoteSnapshot.Line(text: "", stamp: nil)])
        saveNow()
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
}
