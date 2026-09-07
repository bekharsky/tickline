import SwiftUI
import TimedNotesCore
import TimedNotesEditor

struct ContentView: View {
    @ObservedObject var document: TimedNoteDocument
    @Environment(\.undoManager) private var undoManager

    /// Toolbar items are dropped by hand as the window narrows. Letting AppKit
    /// collect them into its overflow menu instead puts the one button that
    /// must stay reachable — Copy — behind a chevron.
    ///
    /// Starts at zero, so the first frame of a narrow window is the small
    /// toolbar rather than a full one that immediately collapses.
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            NoteEditorView(controller: document.editor)
            Divider()
            StatusBar(editor: document.editor, timer: document.timer)
        }
        .frame(minWidth: 420, minHeight: 320)
        .background(WidthReader(width: $width))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                PlayPauseButton(timer: document.timer)
            }
            if width >= 620 {
                ToolbarItem(placement: .navigation) {
                    ResetButton(timer: document.timer)
                }
            }
            ToolbarItem(placement: .navigation) {
                TimerClock(timer: document.timer)
            }
            ToolbarItem(placement: .primaryAction) {
                CopyStampsButton(editor: document.editor, copy: document.copyWithStamps)
            }
        }
        .focusedSceneValue(\.timedNote, document)
        .onAppear {
            // Editing through the document's undo manager is also what tells
            // SwiftUI the note is dirty and enables Save.
            document.editor.hostUndoManager = undoManager
            document.editor.focus()
        }
        .onChange(of: undoManager) { document.editor.hostUndoManager = $0 }
    }
}

/// Reports the window's content width without taking part in the layout.
private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { width = $0 }
        }
    }
}

private struct PlayPauseButton: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        Button(action: timer.toggle) {
            // Titled, not just an icon: whatever the toolbar cannot fit ends up
            // in the overflow menu, where a bare glyph says nothing.
            Label(
                timer.phase.isActive ? "Pause Timer" : "Start Timer",
                systemImage: timer.phase.isActive ? "pause.fill" : "play.fill"
            )
        }
        .help(timer.phase.isActive ? "Pause the timer (⇧⌘P)" : "Start the timer (⇧⌘P)")
    }
}

private struct ResetButton: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        Button {
            timer.reset()
        } label: {
            Label("Reset Timer", systemImage: "arrow.counterclockwise")
        }
        .disabled(timer.phase == .idle)
        .help("Reset the timer (⇧⌘R)")
    }
}

/// The one clock in the app: it counts down next to the transport buttons, and
/// clicking it is how the duration is set. Nothing else in the toolbar repeats
/// the number.
private struct TimerClock: View {
    @ObservedObject var timer: TimerEngine
    @State private var isSettingDuration = false

    var body: some View {
        Button {
            isSettingDuration = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(StampFormatter.string(for: timer.remaining, format: .clock))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .help(helpText)
        .popover(isPresented: $isSettingDuration, arrowEdge: .bottom) {
            DurationEditor(timer: timer)
        }
    }

    /// Colour means "the clock is doing something". A stopped timer — never
    /// started, or paused — is just a number, so it stays plain.
    private var color: Color {
        switch timer.phase {
        case .idle, .paused: return .secondary
        case .running: return .primary
        case .overtime: return .red
        }
    }

    private var helpText: String {
        switch timer.phase {
        case .idle: return "Timer not started — click to set the duration"
        case .running: return "Time left — click to set the duration"
        case .paused: return "Paused — click to set the duration"
        case .overtime: return "Over the planned time — click to set the duration"
        }
    }
}

/// Copies the note the way it looks right now: stamps at the detail level on
/// screen, not the full precision kept in the file.
private struct CopyStampsButton: View {
    @ObservedObject var editor: NoteEditorController
    let copy: () -> Void

    @State private var justCopied = false

    var body: some View {
        Button {
            copy()
            justCopied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                justCopied = false
            }
        } label: {
            Label("Copy with Timestamps", systemImage: justCopied ? "checkmark" : "doc.on.doc")
        }
        .help(helpText)
    }

    private var helpText: String {
        guard !editor.format.isEmpty else {
            return "Copy the selection without timestamps (⇧⌘C)"
        }
        let sample = StampFormatter.string(for: editor.caretStamp?.remaining ?? 3600, format: editor.format)
        return "Copy the selection with timestamps as shown, like [\(sample)] (⇧⌘C)"
    }
}

private struct StatusBar: View {
    @ObservedObject var editor: NoteEditorController
    @ObservedObject var timer: TimerEngine

    var body: some View {
        HStack(spacing: 12) {
            Text("Line \(editor.caretLine + 1) of \(editor.lineCount)")
            Text(stampDescription)
                .monospacedDigit()
            Spacer()
            DetailMenu(format: $editor.format)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var stampDescription: String {
        guard let stamp = editor.caretStamp else {
            return timer.phase == .idle ? "line written before the timer started" : "no stamp yet"
        }
        return "started with \(StampFormatter.string(for: stamp.remaining, format: .exact)) left"
    }
}

/// The detail level lives down here rather than in the toolbar. It is a setting
/// touched rarely, the status bar already had to spell it out, and a menu of
/// named units says far more than four cryptic letters ever did.
private struct DetailMenu: View {
    @Binding var format: StampFormat

    var body: some View {
        Menu {
            Toggle("Hours", isOn: $format.hours)
            Toggle("Minutes", isOn: $format.minutes)
            Toggle("Seconds", isOn: $format.seconds)
            Toggle("Tenths", isOn: $format.subseconds)
                .disabled(!format.seconds)
            Divider()
            Button("Exact Time") { format = .exact }
            Button("Minutes Only") { format = .minutesOnly }
        } label: {
            Text(title)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var title: String {
        guard !format.isEmpty else { return "stamps hidden" }

        var units: [String] = []
        // Lowercase throughout: these are durations, not times of day, so the
        // ICU distinction between H and h has nothing to say here.
        if format.hours { units.append("h") }
        if format.minutes { units.append("m") }
        if format.seconds { units.append(format.subseconds ? "s.1" : "s") }
        return units.joined(separator: ":")
    }
}

private struct DurationEditor: View {
    @ObservedObject var timer: TimerEngine

    @State private var hours = 1
    @State private var minutes = 0
    @State private var seconds = 0

    private let presets: [(String, TimeInterval)] = [
        ("15m", 15 * 60),
        ("25m", 25 * 60),
        ("45m", 45 * 60),
        ("1h", 3600),
        ("1h30", 90 * 60),
        ("2h", 2 * 3600)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer duration")
                .font(.headline)

            HStack(spacing: 6) {
                ForEach(presets, id: \.0) { preset in
                    Button(preset.0) { apply(duration: preset.1) }
                }
            }

            Divider()

            HStack(spacing: 14) {
                Stepper("Hours: \(hours)", value: $hours, in: 0...23)
                Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                Stepper("Seconds: \(seconds)", value: $seconds, in: 0...59)
            }
            .monospacedDigit()

            if timer.phase.isActive {
                Text("The running timer shifts by the difference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear(perform: seedFields)
        .onChange(of: hours) { _ in pushFields() }
        .onChange(of: minutes) { _ in pushFields() }
        .onChange(of: seconds) { _ in pushFields() }
    }

    private func seedFields() {
        let total = Int(timer.duration.rounded())
        hours = total / 3600
        minutes = (total % 3600) / 60
        seconds = total % 60
    }

    private func apply(duration: TimeInterval) {
        timer.setDuration(duration)
        seedFields()
    }

    private func pushFields() {
        timer.setDuration(TimeInterval(hours * 3600 + minutes * 60 + seconds))
    }
}
