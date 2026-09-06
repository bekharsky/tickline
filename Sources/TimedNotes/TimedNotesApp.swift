import SwiftUI
import TimedNotesCore
import TimedNotesEditor

@main
struct TimedNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Timed Notes") {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 760, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { model.startNewSession() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy with Timestamps") { model.copyWithStamps() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandMenu("Timer") {
                TimerCommands(timer: model.timer)
                Divider()
                DetailCommands(editor: model.editor)
                Divider()
                Button("Export…") { model.exportToFile() }
                    .keyboardShortcut("e")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveNow()
    }
}

private struct TimerCommands: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        // Not ⌘⏎: that belongs to the editor, where it breaks a line without
        // starting a new stamp.
        Button(actionTitle) { timer.toggle() }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        Button("Reset Timer") { timer.reset() }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(timer.phase == .idle)
    }

    private var actionTitle: String {
        switch timer.phase {
        case .idle: return "Start Timer"
        case .running, .overtime: return "Pause Timer"
        case .paused: return "Resume Timer"
        }
    }
}

private struct DetailCommands: View {
    @ObservedObject var editor: NoteEditorController

    var body: some View {
        Toggle("Show Hours", isOn: $editor.format.hours)
            .keyboardShortcut("1", modifiers: .command)
        Toggle("Show Minutes", isOn: $editor.format.minutes)
            .keyboardShortcut("2", modifiers: .command)
        Toggle("Show Seconds", isOn: $editor.format.seconds)
            .keyboardShortcut("3", modifiers: .command)
        Toggle("Show Tenths", isOn: $editor.format.subseconds)
            .keyboardShortcut("4", modifiers: .command)
            .disabled(!editor.format.seconds)
        Button("Exact Time") { editor.format = .exact }
            .keyboardShortcut("0", modifiers: .command)
        Button("Minutes Only") { editor.format = .minutesOnly }
            .keyboardShortcut("9", modifiers: .command)
    }
}
