//
//  CLIInstaller.swift
//  MeetingRecorder
//
//  Handles installation of the `ambient` CLI tool to /usr/local/bin
//  on first launch, with user consent.
//

import Foundation
import AppKit

/// Manages installation of the ambient CLI tool
class CLIInstaller {
    static let shared = CLIInstaller()

    private let userDefaultsKey = "hasOfferedCLIInstall"
    private let cliName = "ambient"
    private let installPath = "/usr/local/bin/ambient"

    /// Check if CLI is already installed at the target path
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installPath)
    }

    /// Check if we've already offered to install
    var hasOfferedInstall: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    /// Get the path to the bundled CLI binary
    private var bundledCLIPath: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(cliName)
    }

    /// Offer to install CLI on first launch
    func offerInstallIfNeeded() {
        // Skip if already offered or already installed
        guard !hasOfferedInstall else { return }
        guard !isInstalled else {
            hasOfferedInstall = true
            return
        }

        // Mark as offered
        hasOfferedInstall = true

        // Show install prompt
        DispatchQueue.main.async {
            self.showInstallPrompt()
        }
    }

    /// Show the installation prompt dialog
    private func showInstallPrompt() {
        let alert = NSAlert()
        alert.messageText = "Install Ambient CLI?"
        alert.informativeText = """
        Would you like to install the `ambient` command-line tool?

        This lets you search and access your meeting transcripts from the terminal or AI agents like Claude Code.

        The CLI will be installed to /usr/local/bin/ambient

        You can always install later from Settings.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Never Ask")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Install
            install()
        case .alertThirdButtonReturn:
            // Never ask - already marked as offered
            break
        default:
            // Not now - will offer again next time? No, we mark as offered
            break
        }
    }

    /// Install the CLI to /usr/local/bin
    func install() {
        guard let sourcePath = bundledCLIPath else {
            showError("Could not find bundled CLI")
            return
        }

        guard FileManager.default.fileExists(atPath: sourcePath.path) else {
            showError("CLI binary not found in app bundle")
            return
        }

        // Create /usr/local/bin if it doesn't exist
        let binDir = URL(fileURLWithPath: "/usr/local/bin")
        if !FileManager.default.fileExists(atPath: binDir.path) {
            do {
                try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            } catch {
                // Will likely fail without admin - try the copy anyway
            }
        }

        // Try to copy - this will prompt for admin password via authorization
        let script = """
        do shell script "cp '\(sourcePath.path)' '\(installPath)' && chmod +x '\(installPath)'" with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                if !errorMessage.contains("User canceled") {
                    showError("Failed to install: \(errorMessage)")
                }
                return
            }

            // Success!
            showSuccess()
        } else {
            showError("Could not create installation script")
        }
    }

    /// Uninstall the CLI
    func uninstall() {
        guard isInstalled else { return }

        let script = """
        do shell script "rm '\(installPath)'" with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                if !errorMessage.contains("User canceled") {
                    showError("Failed to uninstall: \(errorMessage)")
                }
            }
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "CLI Installation Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showSuccess() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "CLI Installed Successfully"
            alert.informativeText = """
            The `ambient` command is now available in your terminal.

            Try it out:
              ambient list
              ambient search "keyword"
              ambient help
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
