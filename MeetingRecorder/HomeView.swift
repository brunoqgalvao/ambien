//
//  HomeView.swift
//  MeetingRecorder
//
//  Welcome screen with setup nudges and recent activity
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: MainAppViewModel
    @Binding var selectedTab: NavigationItem
    
    // Greeting based on time of day
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(greeting), Bruno")
                        .font(.brandDisplay(32, weight: .bold))
                        .foregroundColor(.brandTextPrimary)
                    
                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(.brandSerif(18))
                        .foregroundColor(.brandTextSecondary)
                }
                .padding(.top, 20)
                
                // Nudges (if any)
                VStack(spacing: 12) {
                    // OpenAI API Key Nudge
                    if !isApiKeySet() {
                        NudgeCard(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .orange,
                            title: "Add your OpenAI API key",
                            subtitle: "Enable transcription for your meetings",
                            actionTitle: "Add Key",
                            action: {
                                SettingsWindowController.shared.showWindow()
                            }
                        )
                    }

                    // Dictation style suggestion (show when API key is set but AI cleanup not configured)
                    if isApiKeySet() && !isDictationStyleConfigured() {
                        NudgeCard(
                            icon: "wand.and.stars",
                            iconColor: .brandViolet,
                            title: "Customize your dictation style",
                            subtitle: "Add punctuation, paragraphs, and writing style",
                            actionTitle: "Configure",
                            action: {
                                SettingsWindowController.shared.showWindow()
                            }
                        )
                    }
                }
                
                // Quick Actions
                HStack(spacing: 16) {
                    // Record Action
                    Button(action: {
                        print("[HomeView] Record button tapped!")
                        toggleRecordingDirect()
                    }) {
                        HStack {
                            Image(systemName: viewModel.isRecording ? "stop.fill" : "circle.fill")
                                .foregroundColor(viewModel.isRecording ? .white : .brandCoral)
                                .font(.system(size: 12))

                            VStack(alignment: .leading) {
                                Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                                    .font(.brandDisplay(16, weight: .semibold))
                                Text("⌘⇧R")
                                    .font(.brandMono(12))
                                    .opacity(0.8)
                            }
                        }
                        .foregroundColor(viewModel.isRecording ? .white : .brandTextPrimary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: BrandRadius.medium)
                                .fill(viewModel.isRecording ? Color.brandCoral : Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.medium)
                                .stroke(Color.brandBorder, lineWidth: viewModel.isRecording ? 0 : 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Dictation Action
                    Button(action: {
                        print("[HomeView] Dictation button tapped!")
                        startDictation()
                    }) {
                        HStack {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.brandViolet)

                            VStack(alignment: .leading) {
                                Text("Quick Dictation")
                                    .font(.brandDisplay(16, weight: .semibold))
                                Text("⌃⌘D")
                                    .font(.brandMono(12))
                                    .opacity(0.6)
                            }
                        }
                        .foregroundColor(.brandTextPrimary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: BrandRadius.medium)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.medium)
                                .stroke(Color.brandBorder, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Action Items Widget
                ActionItemsHomeWidget(selectedTab: $selectedTab)

                // Recent Activity
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Today")
                            .font(.brandDisplay(20, weight: .semibold))
                        
                        Spacer()
                        
                        Text("\(viewModel.todayMeetings) recordings • \(String(format: "%.1f", viewModel.totalHours)) hrs")
                            .font(.brandMono(12))
                            .foregroundColor(.brandTextSecondary)
                    }
                    
                    if viewModel.meetings.isEmpty {
                        EmptyHomeState(
                            onStartRecording: { viewModel.toggleRecording() },
                            onUploadFile: { /* TODO: implement file upload */ }
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        // Show first 3 meetings
                        ForEach(viewModel.meetings.prefix(3)) { meeting in
                            HomeMeetingRow(meeting: meeting) {
                                // Navigate to meeting
                                selectedTab = .meetings
                                // Selection logic would go here
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Color.brandBackground)
    }
    
    private func isApiKeySet() -> Bool {
        return KeychainHelper.readOpenAIKey() != nil
    }

    private func isDictationStyleConfigured() -> Bool {
        // Check if user has configured their dictation style preferences
        return UserDefaults.standard.bool(forKey: "dictationStyleConfigured")
    }

    private func startDictation() {
        // Start continuous dictation mode (like double-click fn)
        // This shows the pill and starts recording until user presses Escape
        QuickRecordingManager.shared.startContinuousRecording()
    }

    private func toggleRecordingDirect() {
        print("[HomeView] toggleRecordingDirect called")
        Task { @MainActor in
            // Access AudioCaptureManager via shared instance
            let audioManager = AudioCaptureManager.shared

            if audioManager.isRecording {
                print("[HomeView] Stopping recording...")
                _ = try? await audioManager.stopRecording()
                RecordingIslandController.shared.hide()
            } else {
                print("[HomeView] Starting recording...")
                do {
                    try await audioManager.startRecording()
                    print("[HomeView] Recording started, showing island")
                    RecordingIslandController.shared.show(audioManager: audioManager)
                } catch {
                    print("[HomeView] ERROR starting recording: \(error)")
                }
            }
        }
    }
}

struct NudgeCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.brandDisplay(15, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.brandTextSecondary)
            }
            
            Spacer()
            
            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.brandViolet)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.brandViolet.opacity(0.1))
                    .cornerRadius(BrandRadius.small)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.medium)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.medium)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
    }
}

struct HomeMeetingRow: View {
    let meeting: Meeting
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon/Status - minimal: only show error state
                statusIndicator
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.brandDisplay(15, weight: .medium))
                        .foregroundColor(.brandTextPrimary)
                    
                    HStack(spacing: 8) {
                        Text(meeting.startTime.formatted(date: .omitted, time: .shortened))
                        Text("•")
                        Text(formatDuration(meeting.duration))
                        
                        if let app = meeting.sourceApp {
                            Text("•")
                            Text(app)
                        }
                    }
                    .font(.brandMono(11))
                    .foregroundColor(.brandTextSecondary)
                }
                
                Spacer()

                // Cost badge - only visible for beta testers
                if FeatureFlags.shared.showCosts, let cost = meeting.apiCostCents {
                    Text("$\(Double(cost)/100, specifier: "%.2f")")
                        .font(.brandMono(12))
                        .foregroundColor(.brandTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.brandBackground)
                        .cornerRadius(4)
                }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(BrandRadius.medium)
            .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.medium)
                    .stroke(Color.brandBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Minimal status indicator - only shows for errors or in-progress
    @ViewBuilder
    private var statusIndicator: some View {
        switch meeting.status {
        case .recording:
            // Recording pulse
            ZStack {
                Circle()
                    .fill(Color.brandCoral.opacity(0.1))
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(Color.brandCoral)
                    .frame(width: 10, height: 10)
            }
        case .transcribing, .pendingTranscription:
            // Spinner for in-progress
            BrandLoadingIndicator(size: .large)
                .frame(width: 40, height: 40)
        case .failed:
            // Error indicator
            ZStack {
                Circle()
                    .fill(Color.brandCoral.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.brandCoral)
            }
        case .ready:
            // Clean neutral icon - no status color
            ZStack {
                Circle()
                    .fill(Color.brandCreamDark.opacity(0.5))
                    .frame(width: 40, height: 40)
                Image(systemName: meeting.sourceApp == "Dictation" ? "mic.fill" : "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(.brandTextSecondary)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return "\(minutes)m"
    }
}

struct EmptyHomeState: View {
    var onStartRecording: () -> Void = {}
    var onUploadFile: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Text("Meeting notes")
                    .font(.brandDisplay(32, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Text("You haven't created any meeting notes yet.\nAfter your notes are created, they'll appear\nhere for you to view and share.")
                    .font(.system(size: 15))
                    .foregroundColor(.brandTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Feature card
            VStack(spacing: 0) {
                EmptyStateFeatureRow(
                    icon: "video.fill",
                    iconBackground: Color.brandCoral.opacity(0.15),
                    iconColor: .brandCoral,
                    title: "Join a meeting",
                    subtitle: "Automatically record from wherever."
                )

                Divider()
                    .padding(.leading, 56)

                EmptyStateFeatureRow(
                    icon: "sparkles",
                    iconBackground: Color.brandAmber.opacity(0.15),
                    iconColor: .brandAmber,
                    title: "Generate notes",
                    subtitle: "Get the summary, todos, and transcript."
                )

                Divider()
                    .padding(.leading, 56)

                EmptyStateFeatureRow(
                    icon: "sparkle",
                    iconBackground: Color.brandViolet.opacity(0.15),
                    iconColor: .brandViolet,
                    title: "Share it",
                    subtitle: "Send a public link for anyone to view."
                )
            }
            .background(Color.white)
            .cornerRadius(BrandRadius.large)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)

            // Action buttons
            VStack(spacing: 12) {
                Button(action: onStartRecording) {
                    Text("Start a new recording")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .cornerRadius(BrandRadius.large)
                }
                .buttonStyle(.plain)

                Button(action: onUploadFile) {
                    Text("Upload a recording file")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.brandTextPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(BrandRadius.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.large)
                                .stroke(Color.brandBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 500)
        .padding(.vertical, 48)
    }
}

struct EmptyStateFeatureRow: View {
    let icon: String
    let iconBackground: Color
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.brandTextSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
