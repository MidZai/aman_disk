import SwiftUI

public struct Toast: Equatable, Identifiable {
    public let id = UUID()
    public let message: String
    public let systemImage: String
    
    public init(message: String, systemImage: String) {
        self.message = message
        self.systemImage = systemImage
    }
}

@MainActor
public class ToastCenter: ObservableObject {
    public static let shared = ToastCenter()
    
    @Published public var currentToast: Toast?
    
    private var hideTask: Task<Void, Never>?
    
    public func show(message: String, systemImage: String) {
        let toast = Toast(message: message, systemImage: systemImage)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentToast = toast
        }
        
        
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            
            withAnimation(.easeOut(duration: 0.2)) {
                if self.currentToast == toast {
                    self.currentToast = nil
                }
            }
        }
    }
    
    public func suspendDismissal() {
        hideTask?.cancel()
    }
    
    public func resumeDismissal() {
        guard let toast = currentToast else { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            
            withAnimation(.easeOut(duration: 0.2)) {
                if self.currentToast == toast {
                    self.currentToast = nil
                }
            }
        }
    }
}

public struct ToastView: View {
    @ObservedObject var center = ToastCenter.shared
    
    public var body: some View {
        if let toast = center.currentToast {
            HStack(spacing: 8) {
                Image(systemName: toast.systemImage)
                Text(toast.message)
                    .font(.callout)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .padding(.top, 12)
            .onHover { isHovering in
                if isHovering {
                    center.suspendDismissal()
                } else {
                    center.resumeDismissal()
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
            .id(toast.id)
        }
    }
}
