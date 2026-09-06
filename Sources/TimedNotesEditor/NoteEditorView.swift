import SwiftUI

/// SwiftUI wrapper around the controller's scroll view. The controller outlives
/// view updates, so there is nothing to reconfigure here.
public struct NoteEditorView: NSViewRepresentable {
    private let controller: NoteEditorController

    public init(controller: NoteEditorController) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> NSScrollView {
        controller.scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
