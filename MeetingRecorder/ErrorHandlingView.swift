//
//  ErrorHandlingView.swift
//  MeetingRecorder
//
//  Error state views matching WIREFRAMES.md:
//  - Transcription failed
//  - Invalid API key
//  - Network offline
//  - Permission denied recovery
//

import SwiftUI
import Network

// MARK: - Error Types

/// Application-level errors with recovery actions
enum AppError: Identifiable {
    case transcriptionFailed(meeting: Meeting, error: String)
    case invalidAPIKey
    case networkOffline(pendingCount: Int)
    case permissionDenied(permission: PermissionType)
    case deleteConfirmation(meeting: Meeting)

    var id: String {
        switch self {
        case .transcriptionFailed(let meeting, _): return "transcription-\(meeting.id)"
        case .invalidAPIKey: return "invalid-api-key"
        case .networkOffline: return "network-offline"
        case .permissionDenied(let type): return "permission-\(type)"
        case .deleteConfirmation(let meeting): return "delete-\(meeting.id)"
        }
    }

    enum PermissionType: String {
        case microphone = "Microphone"
        case screenRecording = "Screen Recording"
        case accessibility = "Accessibility"

        var systemPreferencesURL: URL? {
            switch self {
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            case .screenRecording:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        }
    }
}

// MARK: - Transcription Failed View

struct TranscriptionFailedView: View {
    let meeting: Meeting
    let errorMessage: String
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Transcription failed")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(meeting.title)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    Text(meeting.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("Audio saved")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                HStack(spacing: 4) {
                    Text("Error:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.top, 4)

                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text("Retry")
                            .frame(width: 70)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onOpenSettings) {
                        Text("Open Settings")
                            .frame(width: 100)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)
        }
        .padding(16)
        .frame(width: 340)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Invalid API Key View

struct InvalidAPIKeyView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings > API")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI")
                    .font(.headline)

                HStack {
                    Text("API Key")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("sk-invalid...")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                }

                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Invalid key")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Warning box
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("This API key is invalid or has been revoked.")
                        .font(.callout)
                    Link("Get a new key at platform.openai.com",
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            HStack {
                Spacer()
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Permission Denied View

struct PermissionDeniedView: View {
    let permissionType: AppError.PermissionType
    let onOpenSystemPreferences: () -> Void
    let onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("\(permissionType.rawValue) Not Enabled")
                    .font(.title2.weight(.semibold))

                Text(descriptionText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onOpenSystemPreferences) {
                Text("Open System Preferences...")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)

            if let onSkip = onSkip {
                Button(action: onSkip) {
                    Text(skipText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(32)
        .frame(width: 400, height: 320)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    private var descriptionText: String {
        switch permissionType {
        case .microphone:
            return "We need this permission to record your voice for dictation and meetings."
        case .screenRecording:
            return "We need this permission to record meeting audio."
        case .accessibility:
            return "We need this permission to paste transcribed text at your cursor."
        }
    }

    private var skipText: String {
        switch permissionType {
        case .screenRecording:
            return "Skip (use mic only)"
        default:
            return "Skip for now"
        }
    }
}

// MARK: - Network Offline View

struct NetworkOfflineView: View {
    let pendingMeetingsCount: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.secondary)
                Text("Offline")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recording saved. Transcription queued.")
                    .font(.subheadline)

                Text("Will process when you're back online.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("\(pendingMeetingsCount) meeting\(pendingMeetingsCount == 1 ? "" : "s") waiting for transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Delete Confirmation View

struct DeleteConfirmationView: View {
    let meeting: Meeting
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Delete \"\(meeting.title)\"?")
                    .font(.headline)

                Text("The recording and transcript will be permanently deleted.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .frame(width: 80)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(width: 80)
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Error Banner (inline)

struct ErrorBanner: View {
    let message: String
    let type: BannerType
    let onDismiss: (() -> Void)?
    let action: ErrorBannerAction?

    enum BannerType {
        case error
        case warning
        case info

        var color: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }

        var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    struct ErrorBannerAction {
        let title: String
        let action: () -> Void
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            if let action = action {
                Button(action.title) {
                    action.action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(type.color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Network Monitor

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Previews

#Preview("Transcription Failed") {
    TranscriptionFailedView(
        meeting: Meeting.sampleMeetings[0],
        errorMessage: "Network timeout",
        onRetry: {},
        onOpenSettings: {},
        onDismiss: {}
    )
}

#Preview("Invalid API Key") {
    InvalidAPIKeyView(
        onOpenSettings: {},
        onDismiss: {}
    )
}

#Preview("Permission Denied - Screen Recording") {
    PermissionDeniedView(
        permissionType: .screenRecording,
        onOpenSystemPreferences: {},
        onSkip: {}
    )
}

#Preview("Permission Denied - Microphone") {
    PermissionDeniedView(
        permissionType: .microphone,
        onOpenSystemPreferences: {},
        onSkip: nil
    )
}

#Preview("Network Offline") {
    NetworkOfflineView(
        pendingMeetingsCount: 1,
        onDismiss: {}
    )
}

#Preview("Delete Confirmation") {
    DeleteConfirmationView(
        meeting: Meeting.sampleMeetings[0],
        onCancel: {},
        onDelete: {}
    )
}

#Preview("Error Banner") {
    VStack(spacing: 16) {
        ErrorBanner(
            message: "Transcription failed for \"Daily Standup\"",
            type: .error,
            onDismiss: {},
            action: ErrorBanner.ErrorBannerAction(title: "Retry", action: {})
        )

        ErrorBanner(
            message: "You're offline. Recordings will sync when connected.",
            type: .warning,
            onDismiss: nil,
            action: nil
        )

        ErrorBanner(
            message: "New update available!",
            type: .info,
            onDismiss: {},
            action: ErrorBanner.ErrorBannerAction(title: "Update", action: {})
        )
    }
    .padding()
    .frame(width: 400)
}
