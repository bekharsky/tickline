import SwiftUI
import TimedNotesCore
import TimedNotesEditor

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NoteEditorView(controller: model.editor)
            Divider()
            StatusBar(editor: model.editor, timer: model.timer)
        }
        .frame(minWidth: 520, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TimerControls(timer: model.timer, model: model)
            }
            ToolbarItem(placement: .principal) {
                RemainingClock(timer: model.timer)
            }
            ToolbarItem(placement: .primaryAction) {
                DetailControls(editor: model.editor)
            }
        }
        .onAppear { model.editor.focus() }
    }
}

private struct TimerControls: View {
    @ObservedObject var timer: TimerEngine
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Button(action: timer.toggle) {
                Image(systemName: timer.phase.isActive ? "pause.fill" : "play.fill")
            }
            .help(timer.phase.isActive ? "Pause the timer (⌘⏎)" : "Start the timer (⌘⏎)")

            Button {
                timer.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(timer.phase == .idle)
            .help("Reset the timer (⇧⌘R)")

            Button {
                model.isDurationEditorPresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(StampFormatter.string(for: timer.duration, format: .clock))
                        .monospacedDigit()
                }
            }
            .help("Set the timer duration")
            .popover(isPresented: $model.isDurationEditorPresented, arrowEdge: .bottom) {
                DurationEditor(timer: timer)
            }
        }
    }
}

private struct RemainingClock: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        Text(StampFormatter.string(for: timer.remaining, format: .clock))
            .font(.system(.title3, design: .monospaced))
            .foregroundStyle(color)
            .help(helpText)
    }

    private var color: Color {
        switch timer.phase {
        case .idle: return .secondary
        case .paused: return .orange
        case .running: return .primary
        case .overtime: return .red
        }
    }

    private var helpText: String {
        switch timer.phase {
        case .idle: return "Timer not started"
        case .running: return "Time left"
        case .paused: return "Paused"
        case .overtime: return "Over the planned time"
        }
    }
}

/// The H / m / s buttons. They only change how stamps are rendered, so any
/// combination can be turned on again later and the exact values come back.
private struct DetailControls: View {
    @ObservedObject var editor: NoteEditorController

    var body: some View {
        HStack(spacing: 6) {
            Toggle("H", isOn: $editor.format.hours)
                .help("Show hours in line stamps (⌘1)")
            Toggle("m", isOn: $editor.format.minutes)
                .help("Show minutes in line stamps (⌘2)")
            Toggle("s", isOn: $editor.format.seconds)
                .help("Show seconds in line stamps (⌘3)")
            Toggle(".1", isOn: $editor.format.subseconds)
                .help("Show tenths of a second (⌘4)")
                .disabled(!editor.format.seconds)

            Button {
                editor.format = .exact
            } label: {
                Image(systemName: "scope")
            }
            .help("Restore full precision (⌘0)")
        }
        .toggleStyle(.button)
        .font(.system(size: 12, design: .monospaced))
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
            Text(StampFormatter.placeholder(for: editor.format).isEmpty ? "stamps hidden" : "detail: \(detailDescription)")
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

    private var detailDescription: String {
        var units: [String] = []
        if editor.format.hours { units.append("H") }
        if editor.format.minutes { units.append("m") }
        if editor.format.seconds { units.append(editor.format.subseconds ? "s.1" : "s") }
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
