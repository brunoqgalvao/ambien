//
//  DeepgramTranscriptionProvider.swift
//  MeetingRecorder
//
//  Deepgram transcription provider - STUB FILE
//  This is a placeholder for future Deepgram integration.
//  The full implementation requires TranscriptionProviderProtocol infrastructure.
//

import Foundation

// MARK: - Deepgram Provider Stub

/// Placeholder for Deepgram transcription provider
/// Full implementation pending unified transcription provider system
class DeepgramTranscriptionProviderStub {
    static let shared = DeepgramTranscriptionProviderStub()

    private init() {}

    var isConfigured: Bool {
        KeychainHelper.readDeepgramKey() != nil
    }

    func validateAPIKey() async -> Bool {
        guard let apiKey = KeychainHelper.readDeepgramKey() else {
            return false
        }

        // Simple validation by checking projects endpoint
        var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}
