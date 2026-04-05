import SwiftUI

// MARK: - Color palette (matches web/Kotlin)

let avatarColors: [String] = ["#d4c4a8", "#b8c9d4", "#c9b8b0", "#b0c9b8", "#c4b8d4"]

// MARK: - Avatar circle (reusable)

struct AvatarCircle: View {
    let profile: Profile
    var size: CGFloat = 80

    private var fontSize: CGFloat { size * 0.35 }

    var body: some View {
        if profile.hasAvatar {
            AsyncImage(url: avatarImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initialsView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color(hex: profile.color) ?? Color(hex: avatarColors[0])!)
                .frame(width: size, height: size)
            Text(profile.initials.isEmpty ? initialsFrom(profile.name) : profile.initials)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(Color(hex: "#1E1D1B")!)
        }
    }

    private var avatarImageURL: URL? {
        // Constructed from server URL stored in UserDefaults
        let base = UserDefaults.standard.string(forKey: "server_url") ?? "https://rpi:8000"
        return URL(string: "\(base)/api/profiles/\(profile.id)/avatar")
    }
}

// MARK: - Profile picker

struct ProfilePickerView: View {
    @Environment(TreadmillStore.self) private var store

    @State private var loading = true
    @State private var showCreate = false
    @State private var errorMessage: String?
    @State private var selecting = false

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView()
                Spacer()
            } else if showCreate {
                Spacer()
                CreateProfileForm(
                    onCreated: { profile in
                        showCreate = false
                        Task {
                            await store.selectProfile(profile.id)
                            store.navigate(to: .lobby)
                        }
                    },
                    onCancel: { showCreate = false }
                )
                .padding(.horizontal, 24)
                Spacer()
            } else {
                pickerContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await store.fetchProfiles()
            loading = false
        }
    }

    private var pickerContent: some View {
        VStack(spacing: 32) {
            Spacer()

            // Header
            Text("Who's running today?")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            // Centered profile avatars — top-aligned so subtitle text doesn't push circles down
            HStack(alignment: .top, spacing: 32) {
                ForEach(store.profiles) { profile in
                    profileButton(profile)
                }
                guestButton
                addButton
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    private func profileButton(_ profile: Profile) -> some View {
        Button {
            guard !selecting else { return }
            selecting = true
            Task {
                await store.selectProfile(profile.id)
                store.navigate(to: .lobby)
                selecting = false
            }
        } label: {
            VStack(spacing: 8) {
                AvatarCircle(profile: profile, size: 88)

                Text(profile.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 88)
            }
        }
        .buttonStyle(.plain)
        .disabled(selecting)
        .opacity(selecting ? 0.5 : 1.0)
    }

    private var guestButton: some View {
        Button {
            guard !selecting else { return }
            selecting = true
            Task {
                await store.startGuestMode()
                store.navigate(to: .lobby)
                selecting = false
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#e8e4df")!, Color(hex: "#d4c4a8")!],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                    Text("👋")
                        .font(.system(size: 32))
                }

                Text("Guest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Jump right in")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .disabled(selecting)
        .opacity(selecting ? 0.5 : 1.0)
    }

    private var addButton: some View {
        Button {
            guard !selecting else { return }
            showCreate = true
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(.tertiary)
                    .frame(width: 88, height: 88)
                    .overlay {
                        Text("+")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)
                    }

                Text("Add")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .disabled(selecting)
        .opacity(selecting ? 0.5 : 1.0)
    }
}

// MARK: - Create profile form

struct CreateProfileForm: View {
    let onCreated: (Profile) -> Void
    let onCancel: () -> Void

    @Environment(TreadmillStore.self) private var store

    @State private var name = ""
    @State private var selectedColor = avatarColors[0]
    @State private var saving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("New Profile")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .onAppear { nameFocused = true }

            // Color picker
            HStack(spacing: 12) {
                ForEach(avatarColors, id: \.self) { c in
                    Circle()
                        .fill(Color(hex: c)!)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selectedColor == c ? Color.primary : Color.clear,
                                    lineWidth: 3
                                )
                        }
                        .onTapGesture { selectedColor = c }
                }
            }

            VStack(spacing: 8) {
                Button("Create", action: submit)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.42, green: 0.784, blue: 0.608), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)

                Button("Cancel", action: onCancel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !saving else { return }
        saving = true
        Task {
            if let profile = await store.createProfile(name: trimmed, color: selectedColor) {
                onCreated(profile)
            }
            saving = false
        }
    }
}

// MARK: - Helpers

func initialsFrom(_ name: String) -> String {
    let parts = name.trimmingCharacters(in: .whitespaces)
        .split(separator: " ")
        .map(String.init)
    if parts.count >= 2, let f = parts.first?.first, let l = parts.last?.first {
        return "\(f)\(l)".uppercased()
    }
    return String(name.prefix(2)).uppercased()
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}
