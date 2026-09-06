import AppKit
import XCTest
@testable import TimedNotesEditor
@testable import TimedNotesCore

/// Renders the gutter offscreen. This is the part that cannot be checked by
/// reasoning alone: stamps only exist on screen, so the drawing has to run.
@MainActor
final class GutterRenderTests: XCTestCase {
    private func makeController(lines: [NoteSnapshot.Line], format: StampFormat) -> NoteEditorController {
        let controller = NoteEditorController()
        controller.scrollView.frame = NSRect(x: 0, y: 0, width: 420, height: 320)
        controller.format = format
        controller.load(lines: lines)
        controller.scrollView.layoutSubtreeIfNeeded()
        controller.scrollView.tile()
        return controller
    }

    private func sampleLines() -> [NoteSnapshot.Line] {
        [
            NoteSnapshot.Line(text: "first line", stamp: LineStamp(remaining: 3600, wallClock: Date())),
            NoteSnapshot.Line(text: "second line", stamp: LineStamp(remaining: 3212.4, wallClock: Date())),
            NoteSnapshot.Line(text: "third line", stamp: LineStamp(remaining: 45.9, wallClock: Date()))
        ]
    }

    /// Number of pixels that differ from the gutter background, i.e. drawn text.
    private func inkPixels(of controller: NoteEditorController, dumpTo name: String? = nil) throws -> Int {
        let gutter = controller.gutter
        gutter.frame = NSRect(x: 0, y: 0, width: gutter.ruleThickness, height: 320)
        let bounds = gutter.bounds
        XCTAssertGreaterThan(bounds.width, 0, "gutter should have a width")

        let rep = try XCTUnwrap(gutter.bitmapImageRepForCachingDisplay(in: bounds))
        gutter.cacheDisplay(in: bounds, to: rep)

        if let name, let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/timed-notes-\(name).png"))
        }

        let background = try XCTUnwrap(rep.colorAt(x: 1, y: 1))
        var ink = 0
        for y in 0..<rep.pixelsHigh {
            // The 1px separator on the right edge is not text.
            for x in 0..<max(0, rep.pixelsWide - 3) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if abs(color.brightnessComponent - background.brightnessComponent) > 0.05 {
                    ink += 1
                }
            }
        }
        return ink
    }

    func testGutterDrawsStamps() throws {
        let controller = makeController(lines: sampleLines(), format: .clock)
        let ink = try inkPixels(of: controller, dumpTo: "clock")
        XCTAssertGreaterThan(ink, 100, "stamps should be visible in the gutter")
    }

    func testLessDetailDrawsLessInk() throws {
        let exact = try inkPixels(of: makeController(lines: sampleLines(), format: .exact), dumpTo: "exact")
        let minutes = try inkPixels(of: makeController(lines: sampleLines(), format: .minutesOnly), dumpTo: "minutes")

        XCTAssertGreaterThan(minutes, 0)
        XCTAssertGreaterThan(exact, minutes, "H:mm:ss.t is wider than minutes only")
    }

    func testTurningEveryUnitOffLeavesTheGutterBlank() throws {
        let format = StampFormat(hours: false, minutes: false, seconds: false)
        let ink = try inkPixels(of: makeController(lines: sampleLines(), format: format), dumpTo: "blank")
        XCTAssertEqual(ink, 0)
    }

    func testGutterWidthFollowsTheFormat() {
        let exact = makeController(lines: sampleLines(), format: .exact)
        let minutes = makeController(lines: sampleLines(), format: .minutesOnly)
        XCTAssertGreaterThan(exact.gutter.ruleThickness, minutes.gutter.ruleThickness)
    }

    /// Switching detail back must bring the original precision back.
    func testDetailChangeIsReversible() throws {
        let controller = makeController(lines: sampleLines(), format: .exact)
        let before = try inkPixels(of: controller)

        controller.format = .minutesOnly
        controller.scrollView.tile()
        let reduced = try inkPixels(of: controller)

        controller.format = .exact
        controller.scrollView.tile()
        let restored = try inkPixels(of: controller)

        XCTAssertLessThan(reduced, before)
        XCTAssertEqual(restored, before)
    }

    func testStampTextUsesStoredPrecision() {
        let controller = makeController(lines: sampleLines(), format: .minutesOnly)
        XCTAssertEqual(controller.stampText(forLine: 1), "53")

        controller.format = .exact
        XCTAssertEqual(controller.stampText(forLine: 1), "00:53:32.4")
    }

    func testLinesWithoutStampsShowAPlaceholder() {
        let controller = makeController(
            lines: [NoteSnapshot.Line(text: "written before the timer", stamp: nil)],
            format: .clock
        )
        XCTAssertEqual(controller.stampText(forLine: 0), "--:--:--")
    }
}
