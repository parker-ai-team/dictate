import Foundation
import AppKit

// Clipboard paste, then restore. Chosen over synthetic keystrokes because it
// is one event, works in every text field that accepts Cmd+V (browsers,
// Notes, Slack, Electron apps) and handles Unicode and newlines without the
// keyboard-layout problems of per-character key events. The cost: the
// pasteboard is touched for about 400 ms. Previous contents are put back.
enum TextInserter {
    static let restoreDelay: TimeInterval = 0.4

    // Characters that may legitimately end a dictation without a full stop.
    private static let terminalEndings: Set<Character> = [
        ".", "?", "!", "…", ":", ";",
        "\"", "”", "“", "'", "’", "»", "«", ")", "]", "}",
    ]

    // Applied to every insertion (formatted, raw fallback, formatting off):
    // prose gets a terminal full stop if it has none, then exactly one
    // trailing space so the next dictation does not glue onto this one.
    // List output keeps its punctuation and gets a trailing newline instead.
    static func finalize(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let isList = t.hasPrefix("- ") || t.contains("\n- ")
        if isList { return t + "\n" }
        if let last = t.last, !terminalEndings.contains(last) {
            t += "."
        }
        return t + " "
    }

    // Markers from the nspasteboard.org convention. Clipboard managers that
    // honour it (Paste, Maccy, Raycast and others) skip the item, and
    // ConcealedType also asks them not to keep a history copy. macOS itself
    // does not enforce them; the item is still on the general pasteboard for
    // the restoreDelay window.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        item.setData(Data(), forType: concealedType)
        pb.writeObjects([item])
        postCommandV()
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            restore(pb, items: saved)
        }
    }

    static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9  // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private static func restore(_ pb: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let newItems: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(newItems)
    }
}
