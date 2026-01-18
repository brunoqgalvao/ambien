//
//  SpeakerProfilesSettingsView.swift
//  MeetingRecorder
//
//  Settings view for managing speaker profiles (voice embeddings)
//  Shows named speakers on top, unnamed collapsed below
//

import SwiftUI

// MARK: - Main Settings View

/// Settings view for speaker profiles with voice embeddings
struct SpeakerProfilesSettingsView: View {
    @StateObject private var profileManager = SpeakerProfileManager.shared
    @State private var showUnnamed = false
    @State private var editingProfile: SpeakerProfile?
    @State private var editedName = ""
    @State private var showingDeleteConfirmation = false
    @State private var profileToDelete: SpeakerProfile?
    @State private var showingServiceConfig = false

    // Voice embedding service configuration
    @AppStorage("voiceEmbeddingServiceURL") private var serviceURL = ""
    @State private var serviceAPIKey = ""
    @State private var isServiceHealthy = false
    @State private var isCheckingHealth = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Service configuration
                serviceConfigSection

                Divider()

                // Named speakers (always visible)
                namedSpeakersSection

                // Unnamed speakers (collapsible)
                unnamedSpeakersSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.brandBackground)
        .task {
            await profileManager.loadProfiles()
            serviceAPIKey = KeychainHelper.readVoiceEmbeddingKey() ?? ""
            await checkServiceHealth()
        }
        .sheet(item: $editingProfile) { profile in
            EditSpeakerSheet(
                profile: profile,
                onSave: { name in
                    Task {
                        try? await profileManager.updateName(profile.id, name: name)
                    }
                }
            )
        }
        .alert("Delete Speaker Profile?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    Task {
                        try? await profileManager.deleteProfile(profile.id)
                    }
                }
            }
        } message: {
            Text("This will remove the speaker's voice profile. They may be detected as a new speaker in future meetings.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(.brandViolet)

                Text("Speaker Profiles")
                    .font(.brandDisplay(20, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                if profileManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            Text("Manage speaker voice profiles for automatic identification across meetings.")
                .font(.brandDisplay(13))
                .foregroundColor(.brandTextSecondary)
        }
    }

    // MARK: - Service Configuration

    private var serviceConfigSection: some View {
        BrandCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(.brandViolet)
                    Text("Voice Embedding Service")
                        .font(.brandDisplay(14, weight: .semibold))

                    Spacer()

                    // Status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isServiceHealthy ? Color.brandMint : Color.brandCoral)
                            .frame(width: 8, height: 8)
                        Text(isServiceHealthy ? "Connected" : "Not configured")
                            .font(.brandDisplay(11))
                            .foregroundColor(.brandTextSecondary)
                    }
                }

                if showingServiceConfig {
                    VStack(alignment: .leading, spacing: 12) {
                        // Service URL
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Service URL")
                                .font(.brandDisplay(11, weight: .medium))
                                .foregroundColor(.brandTextSecondary)

                            TextField("https://your-service.fly.dev", text: $serviceURL)
                                .textFieldStyle(.plain)
                                .font(.brandMono(12))
                                .padding(8)
                                .background(Color.brandSurface)
                                .cornerRadius(BrandRadius.small)
                        }

                        // API Key
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key")
                                .font(.brandDisplay(11, weight: .medium))
                                .foregroundColor(.brandTextSecondary)

                            SecureField("your-api-key", text: $serviceAPIKey)
                                .textFieldStyle(.plain)
                                .font(.brandMono(12))
                                .padding(8)
                                .background(Color.brandSurface)
                                .cornerRadius(BrandRadius.small)
                        }

                        HStack {
                            Button(action: saveServiceConfig) {
                                Text("Save")
                                    .font(.brandDisplay(12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brandViolet)

                            Button(action: {
                                Task { await checkServiceHealth() }
                            }) {
                                HStack(spacing: 4) {
                                    if isCheckingHealth {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                    }
                                    Text("Test Connection")
                                }
                                .font(.brandDisplay(12))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.brandViolet)
                        }
                    }
                    .padding(.top, 8)
                }

                Button(action: { withAnimation { showingServiceConfig.toggle() } }) {
                    HStack {
                        Text(showingServiceConfig ? "Hide configuration" : "Configure service")
                            .font(.brandDisplay(12))
                        Image(systemName: showingServiceConfig ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.brandViolet)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Named Speakers Section

    private var namedSpeakersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Named Speakers")
                    .font(.brandDisplay(14, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Text("(\(profileManager.namedProfiles.count))")
                    .font(.brandDisplay(12))
                    .foregroundColor(.brandTextSecondary)
            }

            if profileManager.namedProfiles.isEmpty {
                emptyStateView(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "No named speakers yet",
                    subtitle: "Name speakers in meetings to build your voice library"
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(profileManager.namedProfiles) { profile in
                        SpeakerProfileRow(
                            profile: profile,
                            onEdit: { editingProfile = profile },
                            onDelete: {
                                profileToDelete = profile
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Unnamed Speakers Section

    private var unnamedSpeakersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { showUnnamed.toggle() } }) {
                HStack {
                    Text("Unnamed Speakers")
                        .font(.brandDisplay(14, weight: .semibold))
                        .foregroundColor(.brandTextPrimary)

                    Text("(\(profileManager.unnamedProfiles.count))")
                        .font(.brandDisplay(12))
                        .foregroundColor(.brandTextSecondary)

                    Spacer()

                    Image(systemName: showUnnamed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.brandTextSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showUnnamed {
                if profileManager.unnamedProfiles.isEmpty {
                    emptyStateView(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No unnamed speakers",
                        subtitle: "Speaker profiles will appear here when detected"
                    )
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(profileManager.unnamedProfiles) { profile in
                            SpeakerProfileRow(
                                profile: profile,
                                onEdit: { editingProfile = profile },
                                onDelete: {
                                    profileToDelete = profile
                                    showingDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Views

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.brandTextSecondary.opacity(0.5))

            Text(title)
                .font(.brandDisplay(13, weight: .medium))
                .foregroundColor(.brandTextSecondary)

            Text(subtitle)
                .font(.brandDisplay(11))
                .foregroundColor(.brandTextSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.brandSurface.opacity(0.5))
        .cornerRadius(BrandRadius.medium)
    }

    // MARK: - Actions

    private func saveServiceConfig() {
        _ = KeychainHelper.saveVoiceEmbeddingKey(serviceAPIKey)
        Task {
            await VoiceEmbeddingClient.shared.configure(baseURL: serviceURL, apiKey: serviceAPIKey)
            await checkServiceHealth()
        }
    }

    private func checkServiceHealth() async {
        isCheckingHealth = true
        defer { isCheckingHealth = false }

        await VoiceEmbeddingClient.shared.loadConfiguration()
        isServiceHealthy = await VoiceEmbeddingClient.shared.healthCheck()
    }
}

// MARK: - Speaker Profile Row

struct SpeakerProfileRow: View {
    let profile: SpeakerProfile
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    private var colorForProfile: Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .mint]
        return colors[abs(profile.id.hashValue) % colors.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(colorForProfile)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(profile.initial)
                        .font(.brandDisplay(16, weight: .semibold))
                        .foregroundColor(.white)
                )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.brandDisplay(14, weight: .medium))
                    .foregroundColor(.brandTextPrimary)

                HStack(spacing: 8) {
                    Text("\(profile.meetingCount) meeting\(profile.meetingCount == 1 ? "" : "s")")
                        .font(.brandDisplay(11))
                        .foregroundColor(.brandTextSecondary)

                    if let lastSeen = profile.lastSeenAt {
                        Text("•")
                            .foregroundColor(.brandTextSecondary)
                        Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                            .font(.brandDisplay(11))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
            }

            Spacer()

            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(.brandViolet)
                    }
                    .buttonStyle(.plain)
                    .help("Edit name")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.brandCoral)
                    }
                    .buttonStyle(.plain)
                    .help("Delete profile")
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(isHovered ? Color.brandSurface : Color.clear)
        .cornerRadius(BrandRadius.small)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Edit Speaker Sheet

struct EditSpeakerSheet: View {
    let profile: SpeakerProfile
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Edit Speaker")
                    .font(.brandDisplay(16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.brandTextSecondary)
                }
                .buttonStyle(.plain)
            }

            // Avatar and name
            VStack(spacing: 16) {
                Circle()
                    .fill(Color.brandViolet)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(name.isEmpty ? "?" : String(name.prefix(1)).uppercased())
                            .font(.brandDisplay(24, weight: .semibold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.brandDisplay(11, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    TextField("Enter speaker name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.brandDisplay(14))
                        .padding(12)
                        .background(Color.brandSurface)
                        .cornerRadius(BrandRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                .stroke(Color.brandViolet.opacity(0.5), lineWidth: 1)
                        )
                        .focused($isFocused)
                }
            }

            // Stats
            HStack(spacing: 16) {
                SpeakerStatBadge(label: "Meetings", value: "\(profile.meetingCount)")
                if let confidence = profile.averageConfidence {
                    SpeakerStatBadge(label: "Avg confidence", value: String(format: "%.0f%%", confidence * 100))
                }
            }

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.brandTextSecondary)

                Spacer()

                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandViolet)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320, height: 360)
        .background(Color.brandBackground)
        .onAppear {
            name = profile.name ?? ""
            isFocused = true
        }
    }
}

// MARK: - Speaker Stat Badge

private struct SpeakerStatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.brandDisplay(14, weight: .semibold))
                .foregroundColor(.brandTextPrimary)
            Text(label)
                .font(.brandDisplay(10))
                .foregroundColor(.brandTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.brandSurface)
        .cornerRadius(BrandRadius.small)
    }
}

// MARK: - Preview

#Preview {
    SpeakerProfilesSettingsView()
        .frame(width: 500, height: 600)
}
