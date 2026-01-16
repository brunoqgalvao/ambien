//
//  OnboardingWizard.swift
//  MeetingRecorder
//
//  Professional onboarding wizard with visual permission guides
//  Shows exactly where to click in System Settings
//

import SwiftUI
import ScreenCaptureKit
import AVFoundation

// MARK: - Onboarding Wizard Window Controller

class OnboardingWizardController {
    static let shared = OnboardingWizardController()

    private var windowController: NSWindowController?

    private init() {}

    func showWindow(onComplete: @escaping () -> Void) {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let wizardView = OnboardingWizardView {
            self.windowController?.close()
            self.windowController = nil
            onComplete()
        }

        let hostingController = NSHostingController(rootView: wizardView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ""
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 640, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main Wizard View

struct OnboardingWizardView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var permissionStatus = WizardPermissionStatus()
    @State private var apiKey = ""
    @State private var isValidatingKey = false
    @State private var keyIsValid: Bool?

    let onComplete: () -> Void

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            WizardProgressBar(currentStep: currentStep, totalSteps: totalSteps)

            // Content
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep(onNext: { currentStep = 1 })
                case 1:
                    MicrophonePermissionStep(
                        status: $permissionStatus.microphone,
                        onNext: { currentStep = 2 },
                        onBack: { currentStep = 0 }
                    )
                case 2:
                    ScreenRecordingPermissionStep(
                        status: $permissionStatus.screenRecording,
                        onNext: { currentStep = 3 },
                        onBack: { currentStep = 1 }
                    )
                case 3:
                    APIKeyStep(
                        apiKey: $apiKey,
                        isValidating: $isValidatingKey,
                        isValid: $keyIsValid,
                        onFinish: finishOnboarding,
                        onSkip: finishOnboarding,
                        onBack: { currentStep = 2 }
                    )
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .frame(width: 640, height: 560)
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Progress Bar

struct WizardProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Rectangle()
                    .fill(step <= currentStep ? Color.brandViolet : Color.secondary.opacity(0.2))
                    .frame(height: 3)
            }
        }
    }
}

// MARK: - Permission Status

struct WizardPermissionStatus {
    var microphone: PermissionState = .unknown
    var screenRecording: PermissionState = .unknown
    var accessibility: PermissionState = .unknown

    enum PermissionState {
        case unknown, granted, denied, checking
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero
            VStack(spacing: 24) {
                // App icon
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)
                        .shadow(color: .orange.opacity(0.3), radius: 20, x: 0, y: 10)

                    Image(systemName: "waveform")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 12) {
                    Text("Welcome to MeetingRecorder")
                        .font(.system(size: 28, weight: .bold))

                    Text("Your Mac's memory for everything\nyou say and hear.")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            Spacer()

            // Features
            VStack(spacing: 16) {
                FeatureRow(
                    icon: "mic.fill",
                    iconColor: .blue,
                    title: "Record Meetings",
                    description: "Capture audio from Zoom, Meet, Teams"
                )

                FeatureRow(
                    icon: "text.bubble.fill",
                    iconColor: .green,
                    title: "AI Transcription",
                    description: "Automatic transcripts powered by OpenAI"
                )

                FeatureRow(
                    icon: "keyboard",
                    iconColor: .orange,
                    title: "Dictation Anywhere",
                    description: "Hold hotkey, speak, text appears"
                )
            }
            .padding(.horizontal, 60)

            Spacer()

            // CTA
            Button(action: onNext) {
                Text("Get Started")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 48)
                    .background(Color.brandViolet)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Spacer()
                .frame(height: 32)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Microphone Permission Step

struct MicrophonePermissionStep: View {
    @Binding var status: WizardPermissionStatus.PermissionState
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        PermissionStepLayout(
            icon: "mic.fill",
            iconColor: .blue,
            title: "Microphone Access",
            description: "We need microphone access to record your voice for dictation and meetings.",
            status: status,
            screenshotView: AnyView(MicrophoneScreenshot()),
            instructions: [
                "Click \"Grant Access\" below",
                "A system dialog will appear",
                "Click \"Allow\" to grant permission"
            ],
            onGrant: requestPermission,
            onNext: onNext,
            onBack: onBack
        )
        .onAppear {
            checkPermission()
        }
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            status = .granted
        case .denied, .restricted:
            status = .denied
        case .notDetermined:
            status = .unknown
        @unknown default:
            status = .unknown
        }
    }

    private func requestPermission() {
        status = .checking
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                status = granted ? .granted : .denied
            }
        }
    }
}

// MARK: - Screen Recording Permission Step

struct ScreenRecordingPermissionStep: View {
    @Binding var status: WizardPermissionStatus.PermissionState
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        PermissionStepLayout(
            icon: "rectangle.inset.filled.on.rectangle",
            iconColor: .green,
            title: "Screen Recording",
            description: "This lets us capture system audio from meeting apps like Zoom and Google Meet.",
            status: status,
            screenshotView: AnyView(ScreenRecordingScreenshot()),
            instructions: [
                "Click \"Open System Settings\"",
                "Find \"MeetingRecorder\" in the list",
                "Toggle the switch ON",
                "Click \"Quit & Reopen\" if prompted"
            ],
            onGrant: requestPermission,
            onNext: onNext,
            onBack: onBack
        )
        .onAppear {
            checkPermission()
        }
    }

    private func checkPermission() {
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run {
                    status = .granted
                }
            } catch {
                await MainActor.run {
                    status = .denied
                }
            }
        }
    }

    private func requestPermission() {
        status = .checking
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run {
                    status = .granted
                }
            } catch {
                await MainActor.run {
                    status = .denied
                    // Open System Settings
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }
        }
    }
}

// MARK: - Permission Step Layout

struct PermissionStepLayout: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let status: WizardPermissionStatus.PermissionState
    let screenshotView: AnyView
    let instructions: [String]
    let onGrant: () -> Void
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 64, height: 64)

                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(iconColor)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))

                    Text(description)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }
            .padding(.top, 32)

            Spacer()
                .frame(height: 24)

            // Screenshot mockup
            screenshotView
                .frame(height: 200)
                .padding(.horizontal, 48)

            Spacer()
                .frame(height: 24)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.brandViolet))

                        Text(instruction)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 80)

            Spacer()

            // Status and buttons
            VStack(spacing: 16) {
                // Status indicator
                HStack(spacing: 8) {
                    switch status {
                    case .granted:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Permission granted")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                    case .denied:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.orange)
                        Text("Permission required")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)
                    case .checking:
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Checking...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    case .unknown:
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 16, height: 16)
                        Text("Not checked yet")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                // Buttons
                HStack(spacing: 16) {
                    Button("Back") {
                        onBack()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if status == .granted {
                        Button(action: onNext) {
                            Text("Continue")
                                .frame(width: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button(action: onGrant) {
                            Text(status == .denied ? "Open System Settings" : "Grant Access")
                                .frame(width: 160)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }

            Spacer()
                .frame(height: 32)
        }
    }
}

// MARK: - Screenshot Mockups

struct MicrophoneScreenshot: View {
    var body: some View {
        VStack(spacing: 0) {
            // Mockup of system dialog
            VStack(spacing: 16) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)

                Text("\"MeetingRecorder\" would like to\naccess the microphone.")
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    MockButton(title: "Don't Allow", isPrimary: false)
                    MockButton(title: "Allow", isPrimary: true, isHighlighted: true)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

struct ScreenRecordingScreenshot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar mockup
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.red.opacity(0.8)).frame(width: 12, height: 12)
                    Circle().fill(Color.yellow.opacity(0.8)).frame(width: 12, height: 12)
                    Circle().fill(Color.green.opacity(0.8)).frame(width: 12, height: 12)
                }
                Spacer()
                Text("Privacy & Security")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(Color.clear).frame(width: 12, height: 12)
                    Circle().fill(Color.clear).frame(width: 12, height: 12)
                    Circle().fill(Color.clear).frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.windowBackgroundColor))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text("Screen Recording")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.bottom, 4)

                // App list
                VStack(spacing: 0) {
                    MockAppRow(name: "Zoom", isEnabled: true)
                    Divider().padding(.leading, 44)
                    MockAppRow(name: "MeetingRecorder", isEnabled: false, isHighlighted: true)
                    Divider().padding(.leading, 44)
                    MockAppRow(name: "Chrome", isEnabled: true)
                }
                .background(Color.brandSurface)
                .cornerRadius(8)
            }
            .padding(16)
        }
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct MockAppRow: View {
    let name: String
    let isEnabled: Bool
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 28, height: 28)

            Text(name)
                .font(.system(size: 13))
                .foregroundColor(isHighlighted ? .accentColor : .primary)

            Spacer()

            Toggle("", isOn: .constant(isEnabled))
                .toggleStyle(.switch)
                .scaleEffect(0.7)

            if isHighlighted {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.brandViolet)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHighlighted ? Color.brandViolet.opacity(0.1) : Color.clear)
    }
}

struct MockButton: View {
    let title: String
    let isPrimary: Bool
    var isHighlighted: Bool = false

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: isPrimary ? .semibold : .regular))
            .foregroundColor(isPrimary ? .white : .primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPrimary ? Color.brandViolet : Color.brandSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHighlighted ? Color.brandViolet : Color.clear, lineWidth: 2)
            )
    }
}

// MARK: - API Key Step

struct APIKeyStep: View {
    @Binding var apiKey: String
    @Binding var isValidating: Bool
    @Binding var isValid: Bool?
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var showKey = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 64, height: 64)

                    Image(systemName: "key.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.purple)
                }

                VStack(spacing: 8) {
                    Text("Connect OpenAI")
                        .font(.system(size: 24, weight: .bold))

                    Text("We use your API key for transcription.\nYou only pay for what you use.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 32)

            Spacer()
                .frame(height: 32)

            // API key input
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 8) {
                        Group {
                            if showKey {
                                TextField("sk-...", text: $apiKey)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }

                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        HStack(spacing: 4) {
                            Text("Get your API key")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 12))
                    }
                }

                // Validation status
                if isValidating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Validating...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else if let valid = isValid {
                    HStack(spacing: 8) {
                        Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(valid ? .green : .red)
                        Text(valid ? "API key is valid" : "Invalid API key")
                            .font(.system(size: 13))
                            .foregroundColor(valid ? .green : .red)
                    }
                }
            }
            .padding(.horizontal, 80)

            Spacer()
                .frame(height: 24)

            // Cost info card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundColor(.green)
                    Text("Transparent pricing")
                        .font(.system(size: 14, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 6) {
                    CostRow(label: "Per hour of meetings", cost: "~$0.18")
                    CostRow(label: "Per dictation", cost: "~$0.01")
                    CostRow(label: "Typical monthly cost", cost: "$3-5")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 80)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button("Back") {
                        onBack()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: validateAndFinish) {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Finish Setup")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(apiKey.isEmpty || isValidating)
                    .frame(width: 140)
                }

                Button("Skip for now") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 32)
        }
    }

    private func validateAndFinish() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        isValid = nil

        Task {
            let saved = KeychainHelper.saveOpenAIKey(apiKey)

            if saved {
                let valid = await TranscriptionService.shared.validateAPIKey()

                await MainActor.run {
                    isValidating = false
                    isValid = valid

                    if valid {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onFinish()
                        }
                    }
                }
            } else {
                await MainActor.run {
                    isValidating = false
                    isValid = false
                }
            }
        }
    }
}

struct CostRow: View {
    let label: String
    let cost: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(cost)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: - Previews

#Preview("Welcome") {
    WelcomeStep(onNext: {})
        .frame(width: 640, height: 560)
}

#Preview("Microphone Permission") {
    MicrophonePermissionStep(
        status: .constant(.unknown),
        onNext: {},
        onBack: {}
    )
    .frame(width: 640, height: 560)
}

#Preview("Screen Recording Permission") {
    ScreenRecordingPermissionStep(
        status: .constant(.denied),
        onNext: {},
        onBack: {}
    )
    .frame(width: 640, height: 560)
}

#Preview("API Key") {
    APIKeyStep(
        apiKey: .constant("sk-test-1234"),
        isValidating: .constant(false),
        isValid: .constant(true),
        onFinish: {},
        onSkip: {},
        onBack: {}
    )
    .frame(width: 640, height: 560)
}

#Preview("Full Wizard") {
    OnboardingWizardView(onComplete: {})
}

#Preview("Mic Screenshot") {
    MicrophoneScreenshot()
        .frame(width: 400, height: 200)
        .padding()
}

#Preview("Screen Recording Screenshot") {
    ScreenRecordingScreenshot()
        .frame(width: 400, height: 200)
        .padding()
}
