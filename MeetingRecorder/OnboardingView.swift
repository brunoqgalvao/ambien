//
//  OnboardingView.swift
//  MeetingRecorder
//
//  First-run wizard: Welcome → Permissions → API Key setup
//

import SwiftUI
import ScreenCaptureKit
import AVFoundation

/// Tracks which permissions have been granted
struct PermissionStatus: Equatable {
    var microphone: PermissionState = .unknown
    var screenRecording: PermissionState = .unknown
    var accessibility: PermissionState = .unknown

    enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
        case notDetermined
    }

    var allGranted: Bool {
        microphone == .granted && screenRecording == .granted && accessibility == .granted
    }

    var minimumGranted: Bool {
        // At minimum need mic for basic functionality
        microphone == .granted
    }
}

/// Main onboarding view with step navigation
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep: OnboardingStep = .welcome
    @State private var permissionStatus = PermissionStatus()
    @State private var apiKey: String = ""
    @State private var isValidatingKey = false
    @State private var keyValidationResult: KeyValidationResult?

    let onComplete: () -> Void

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case permissions = 1
        case apiKey = 2

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .apiKey: return "API Key"
            }
        }
    }

    enum KeyValidationResult {
        case valid
        case invalid
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView(onContinue: { currentStep = .permissions })
                case .permissions:
                    PermissionsStepView(
                        permissionStatus: $permissionStatus,
                        onContinue: { currentStep = .apiKey },
                        onBack: { currentStep = .welcome }
                    )
                case .apiKey:
                    APIKeyStepView(
                        apiKey: $apiKey,
                        isValidating: $isValidatingKey,
                        validationResult: $keyValidationResult,
                        onFinish: completeOnboarding,
                        onSkip: completeOnboarding,
                        onBack: { currentStep = .permissions }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Step indicators
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == currentStep ? Color.brandViolet : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 500, height: 450)
        .background(Color(.windowBackgroundColor))
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon placeholder
            ZStack {
                Circle()
                    .fill(Color.brandViolet.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.brandViolet)
            }

            VStack(spacing: 8) {
                Text("Welcome to MeetingRecorder")
                    .font(.title.weight(.semibold))

                Text("Your Mac's memory for everything\nyou say and hear.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 160, height: 44)
                    .background(Color.brandViolet)
                    .cornerRadius(BrandRadius.medium)
            }
            .buttonStyle(.plain)

            Spacer()
                .frame(height: 40)
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Permissions Step

struct PermissionsStepView: View {
    @Binding var permissionStatus: PermissionStatus
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Grant Permissions")
                    .font(.title2.weight(.semibold))

                Text("We need a few permissions to record your meetings\nand enable system-wide dictation.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    iconColor: .blue,
                    title: "Microphone",
                    description: "Record your voice for dictation",
                    state: permissionStatus.microphone,
                    onGrant: requestMicrophonePermission
                )

                PermissionRow(
                    icon: "rectangle.inset.filled.on.rectangle",
                    iconColor: .green,
                    title: "Screen Recording",
                    description: "Capture system audio from meetings",
                    state: permissionStatus.screenRecording,
                    onGrant: requestScreenRecordingPermission
                )

                PermissionRow(
                    icon: "keyboard",
                    iconColor: .orange,
                    title: "Accessibility",
                    description: "Paste transcribed text at cursor",
                    state: permissionStatus.accessibility,
                    onGrant: requestAccessibilityPermission
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 16) {
                Button("Back") {
                    onBack()
                }
                .buttonStyle(.bordered)

                Button(action: onContinue) {
                    Text("Continue")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!permissionStatus.minimumGranted)
            }

            if !permissionStatus.allGranted && permissionStatus.minimumGranted {
                Text("Some permissions are optional. You can grant them later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 20)
        }
        .onAppear {
            checkAllPermissions()
        }
    }

    private func checkAllPermissions() {
        // Check microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionStatus.microphone = .granted
        case .denied, .restricted:
            permissionStatus.microphone = .denied
        case .notDetermined:
            permissionStatus.microphone = .notDetermined
        @unknown default:
            permissionStatus.microphone = .unknown
        }

        // Check screen recording (async)
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run {
                    permissionStatus.screenRecording = .granted
                }
            } catch {
                await MainActor.run {
                    permissionStatus.screenRecording = .denied
                }
            }
        }

        // Check accessibility
        let accessibilityGranted = AXIsProcessTrusted()
        permissionStatus.accessibility = accessibilityGranted ? .granted : .denied
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                permissionStatus.microphone = granted ? .granted : .denied
            }
        }
    }

    private func requestScreenRecordingPermission() {
        // ScreenCaptureKit will prompt automatically when we try to access content
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run {
                    permissionStatus.screenRecording = .granted
                }
            } catch {
                await MainActor.run {
                    permissionStatus.screenRecording = .denied
                    // Open System Preferences
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        permissionStatus.accessibility = trusted ? .granted : .denied
    }
}

struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let state: PermissionStatus.PermissionState
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            switch state {
            case .granted:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                    Text("Done")
                        .font(.caption)
                }
                .foregroundColor(.green)
            case .denied:
                Button("Grant") {
                    onGrant()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .notDetermined, .unknown:
                Button("Grant") {
                    onGrant()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.brandSurface)
        .cornerRadius(BrandRadius.medium)
    }
}

// MARK: - API Key Step

struct APIKeyStepView: View {
    @Binding var apiKey: String
    @Binding var isValidating: Bool
    @Binding var validationResult: OnboardingView.KeyValidationResult?
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var showKey = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Connect OpenAI")
                    .font(.title2.weight(.semibold))

                Text("We use your API key for transcription.\nYou pay only for what you use.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI API Key")
                    .font(.subheadline.weight(.medium))

                HStack {
                    Group {
                        if showKey {
                            TextField("sk-...", text: $apiKey)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Link("Don't have one? Get it at platform.openai.com",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
                    .foregroundColor(.brandViolet)

                // Validation status
                if isValidating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Validating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let result = validationResult {
                    HStack {
                        switch result {
                        case .valid:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API key is valid")
                                .font(.caption)
                                .foregroundColor(.green)
                        case .invalid:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Invalid API key")
                                .font(.caption)
                                .foregroundColor(.red)
                        case .error(let message):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 48)

            // Cost info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Typical cost: ~$0.18/hour of meetings")
                        .font(.callout)
                }
                Text("That's about $4/month for most users.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brandViolet.opacity(0.05))
            .cornerRadius(BrandRadius.medium)
            .padding(.horizontal, 48)

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button("Back") {
                        onBack()
                    }
                    .buttonStyle(.bordered)

                    Button(action: validateAndFinish) {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Finish Setup")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty || isValidating)
                    .frame(width: 120)
                }

                Button("Skip for now") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 20)
        }
    }

    private func validateAndFinish() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        validationResult = nil

        Task {
            // Save the key first
            let saved = KeychainHelper.saveOpenAIKey(apiKey)

            if saved {
                // Validate with OpenAI
                let isValid = await TranscriptionService.shared.validateAPIKey()

                await MainActor.run {
                    isValidating = false
                    if isValid {
                        validationResult = .valid
                        // Small delay to show success, then complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onFinish()
                        }
                    } else {
                        validationResult = .invalid
                    }
                }
            } else {
                await MainActor.run {
                    isValidating = false
                    validationResult = .error("Failed to save API key")
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Welcome") {
    WelcomeStepView(onContinue: {})
        .frame(width: 500, height: 450)
}

#Preview("Permissions") {
    PermissionsStepView(
        permissionStatus: .constant(PermissionStatus(
            microphone: .granted,
            screenRecording: .notDetermined,
            accessibility: .denied
        )),
        onContinue: {},
        onBack: {}
    )
    .frame(width: 500, height: 450)
}

#Preview("API Key") {
    APIKeyStepView(
        apiKey: .constant("sk-test-1234"),
        isValidating: .constant(false),
        validationResult: .constant(.valid),
        onFinish: {},
        onSkip: {},
        onBack: {}
    )
    .frame(width: 500, height: 450)
}

#Preview("Full Onboarding") {
    OnboardingView(onComplete: {})
}
