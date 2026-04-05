import SwiftUI

struct SetupView: View {
    @Environment(TreadmillStore.self) private var store
    @State private var urlText = "https://rpi:8000"
    @State private var connecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Treddy")
                .font(.largeTitle.weight(.bold))

            Text("Enter your treadmill server address")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Server URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(maxWidth: 360)
                    .onSubmit(connect)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(action: connect) {
                    if connecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                .frame(maxWidth: 360)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let saved = UserDefaults.standard.string(forKey: "server_url") ?? ""
            if !saved.isEmpty { urlText = saved }
        }
    }

    private func connect() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !connecting else { return }

        // Basic URL validation
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            errorMessage = "URL must start with http:// or https://"
            return
        }

        connecting = true
        errorMessage = nil
        store.serverURL = trimmed

        // Poll for connection with timeout
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(500))
                if store.isConnected {
                    store.completeSetup()
                    connecting = false
                    return
                }
            }
            errorMessage = "Could not connect to \(trimmed)"
            connecting = false
        }
    }
}

#Preview {
    SetupView()
        .environment(TreadmillStore())
}
