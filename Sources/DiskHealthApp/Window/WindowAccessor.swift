import SwiftUI
import AppKit

class WindowHoverTracker: NSResponder {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private weak var window: NSWindow?
    private var observer: Any?
    
    init(onHover: ((Bool) -> Void)?) {
        self.onHover = onHover
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup(for window: NSWindow) {
        self.window = window
        updateTrackingArea()
        
        // Ensure we update the tracking area if the window resizes
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.updateTrackingArea()
        }
    }
    
    private func updateTrackingArea() {
        guard let window = window, let contentView = window.contentView else { return }
        
        if let existing = trackingArea {
            contentView.removeTrackingArea(existing)
        }
        
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        
        let newTrackingArea = NSTrackingArea(
            rect: .zero, // .inVisibleRect ignores this rect and uses the view's bounds
            options: options,
            owner: self,
            userInfo: nil
        )
        
        contentView.addTrackingArea(newTrackingArea)
        self.trackingArea = newTrackingArea
    }
    
    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    var onHover: ((Bool) -> Void)?
    
    func makeCoordinator() -> WindowHoverTracker {
        WindowHoverTracker(onHover: onHover)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
                if onHover != nil {
                    context.coordinator.setup(for: window)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onHover = onHover
    }
}

extension View {
    func windowAccessor(onWindow: @escaping (NSWindow) -> Void, onHover: ((Bool) -> Void)? = nil) -> some View {
        background(WindowAccessor(onWindow: onWindow, onHover: onHover))
    }
}
