import SwiftUI

struct DisconnectBanner: View {
    var body: some View {
        Text("Disconnected from server")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.red.opacity(0.85))
            .accessibilityIdentifier("disconnect-banner")
    }
}
