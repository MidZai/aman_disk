import SwiftUI

struct UnsupportedDiskView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text(Strings.unsupportedTitle)
                .font(.headline)
            
            VStack(spacing: 12) {
                Text(Strings.unsupportedText1)
                Text(Strings.unsupportedText2)
            }
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)
            
            HStack(spacing: 12) {
                Button(Strings.exportDiagnostic) {}
                Button(Strings.viewSupported) {}
                    .buttonStyle(.link)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
