import Foundation
import AppKit
import SwiftUI

final class IndicatorModel: ObservableObject {
    @Published var text: String = ""
    @Published var color: Color = .red
}

private struct PillView: View {
    @ObservedObject var model: IndicatorModel
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(model.color).frame(width: 10, height: 10)
            Text(model.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.80))
        .clipShape(Capsule())
        .frame(width: 260, height: 36)
    }
}

// Floating pill at the bottom of the main screen. Non-activating, so focus
// stays in the app the user is dictating into.
final class Indicator {
    private let model = IndicatorModel()
    private var panel: NSPanel?
    private var hideTimer: Timer?

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 36),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: PillView(model: model))
        return p
    }

    private func position(_ p: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        let x = f.midX - 130
        let y = f.minY + 48
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show(_ text: String, color: Color = .red, autoHide: TimeInterval? = nil) {
        hideTimer?.invalidate()
        model.text = text
        model.color = color
        let p = panel ?? makePanel()
        panel = p
        position(p)
        p.orderFrontRegardless()
        if let autoHide {
            hideTimer = Timer.scheduledTimer(withTimeInterval: autoHide, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
    }
}
