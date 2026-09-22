import SwiftUI

struct SudoRequestView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Privilèges requis")
                .font(.headline)
            
            Text("La lecture de l'état de santé NVMe nécessite un accès administrateur sur certaines machines. Relancez l'application en mode root via le terminal (sudo).")
                .multilineTextAlignment(.center)
                .frame(width: 300)
            
            Button("Continuer sans privilèges") {
                onContinue()
            }
            .padding(.top, 12)
        }
        .padding(32)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
        .shadow(radius: 20)
    }
}
