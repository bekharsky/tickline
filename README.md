# Timed Notes

A native macOS notepad on a countdown. Start a timer, write, and every new line
is marked with the time that was left when you began it.

The point is the detail level. The app always stores the exact moment a line
started, down to fractions of a second, but shows only the units you asked for.
On a one-hour timer you can keep just minutes on screen and get the full
`00:53:32.4` back at any time, including long after the writing is done.

```
01:00:00  first thought
00:53:32  something else came up
00:00:45  wrapping up
-00:02:10  one more thing after the bell
```

## How it works

Stamps are not part of the text. Each paragraph has a stamp stored next to it and
drawn in the left gutter, so a timestamp cannot be typed over, deleted by
accident, or copied into the middle of a sentence — and changing the detail level
is only a redraw.

- **Return starts a new line, and a new stamp.** Splitting an old line stamps the
  new tail; editing inside a line keeps its original stamp.
- **⌘Return breaks a line without a new stamp.** The text moves to the next
  visual row but stays in the same paragraph, so it keeps the stamp it already
  has. ⌥Return does the same.
- **Pasting a block** stamps every line it creates with the current time left.
- **A line written before the timer started** has no stamp and shows `--:--:--`.
  It gets a real one the moment you keep writing on it with the timer running.
- **Overtime keeps counting.** After the bell, stamps go negative instead of
  stopping at zero.

## Toolbar

| Control | What it does |
| --- | --- |
| ▶︎ / ▮▮ | Start, pause, resume (⇧⌘P) |
| ↺ | Reset the timer (⇧⌘R) |
| ⏱ `1:00:00` | Set the duration. Changing it mid-session moves the deadline by the difference |
| `H` `m` `s` `.1` | Which units the line stamps show (⌘1 … ⌘4) |
| ⌖ | Restore full precision (⌘0). ⌘9 drops back to minutes only |
| ⧉ | Copy with timestamps exactly as shown (⇧⌘C) |

Turning a larger unit off rolls it into the next one: with `H` off, an hour left
reads as `60` minutes, not `00`. Turning everything off hides the gutter.

**Copy with Timestamps** — the ⧉ button, ⇧⌘C, or the Edit menu — puts the stamps
back in front of the lines you selected, cutting the first and last line down to
the selection and keeping their stamps. With nothing selected it copies the whole
note. It always uses the detail on screen, never the full precision from the
file, so pasting minutes-only notes elsewhere stays clean; with every unit off it
copies bare text. A plain ⌘C still copies the text alone, and **Export as Text…**
(⌘E) writes the stamped version to any file.

A line broken with ⌘Return is copied as a real newline indented under the stamp
column, so one screen line stays one line of output.

## Files

Notes are ordinary documents: ⌘N, ⌘O, ⌘S, Save As, several windows at once, each
with its own timer. A note is saved as `.timednote`, which is Markdown inside, so
any editor or Quick Look can read it:

```
---
timer: 01:00:00
remaining: 00:41:12.400
detail: H:m
---

[00:59:56.246] started the review
[00:58:12.900] the numbers in section 3 do not add up
               checked twice, still off by 400
[--:--:--.---] jotted down before the timer started
```

Stamps in the file are always written at full precision, whatever the toolbar
shows, so the detail level stays free to change after reopening. The front matter
carries the timer setup, and lines you broke with ⌘Return come back indented.
Plain `.txt` and `.md` files open too: lines with a `[HH:MM:SS.mmm]` prefix keep
their stamps, everything else becomes unstamped lines.

A reopened note starts **paused** — real time passed while the file was closed,
and pretending otherwise would corrupt every later stamp.

Two things the file does not carry: the calendar time each line was written (it
records offsets from the timer instead), and shortened stamps like `[45]` from a
copied note, which are ambiguous between minutes and seconds and so are read as
plain text.

## Build and run

```sh
swift build                     # libraries + app
swift test                      # 53 tests, no UI session needed
./Packaging/build-app.sh        # dist/TimedNotes.app, ad-hoc signed
open dist/TimedNotes.app
```

To sign with your own identity, copy `Local.xcconfig.example` to
`Local.xcconfig` and fill it in. That file is gitignored.

Requires macOS 13 or later.

## Layout

| Target | Contents |
| --- | --- |
| `TimedNotesCore` | Timer, stamp formatting, and the bookkeeping that keeps stamps aligned with the text through arbitrary edits. No UI. |
| `TimedNotesEditor` | The AppKit text view and the gutter that draws the stamps. The gutter is a plain sibling view with its own layout, not an `NSRulerView`: the ruler tiling machinery fights SwiftUI's sizing of the scroll view and offsets the clip view until the text stops being drawn at all. |
| `TimedNotes` | SwiftUI app, toolbar, menu commands, autosave. |

The split exists so the risky parts can be tested: `StampBookkeeperTests` replays
real typing sequences, `TypingTests` types into a live text view, and
`GutterRenderTests` renders offscreen — including a note hosted in a real SwiftUI
window, which is how the missing-text bug above was found and is kept from
returning.

## Known gaps

- Undo restores the text, but a line recreated by undo is stamped with the time
  at which you pressed undo, not its original one.
