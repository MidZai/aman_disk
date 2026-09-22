import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func windowAccessor(onWindow: @escaping (NSWindow) -> Void) -> some View {
        background(WindowAccessor(onWindow: onWindow))
    }
}
