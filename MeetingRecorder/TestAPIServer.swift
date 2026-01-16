//
//  TestAPIServer.swift
//  MeetingRecorder
//
//  Local HTTP API server for automated testing
//  Exposes backend actions via REST endpoints
//
//  Usage:
//    1. Enable in Debug menu or set ENABLE_TEST_API=1 env var
//    2. Server runs on http://localhost:8765
//    3. Use curl or any HTTP client to test
//

import Foundation
import Network

/// Local HTTP server for testing backend functionality
@MainActor
class TestAPIServer: ObservableObject {
    static let shared = TestAPIServer()

    @Published var isRunning = false
    @Published var lastRequest: String?

    private var listener: NWListener?
    private let port: UInt16 = 8765
    private let queue = DispatchQueue(label: "com.meetingrecorder.testapi")

    // MARK: - Server Control

    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            let serverPort = port
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("[TestAPIServer] Running on http://localhost:\(serverPort)")
                    case .failed(let error):
                        print("[TestAPIServer] Failed: \(error)")
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleConnection(connection)
                }
            }

            listener?.start(queue: queue)

        } catch {
            print("[TestAPIServer] Failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("[TestAPIServer] Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data = data, let request = String(data: data, encoding: .utf8) {
                self?.handleRequest(request, connection: connection)
            } else if let error = error {
                print("[TestAPIServer] Receive error: \(error)")
                connection.cancel()
            }
        }
    }

    private func handleRequest(_ request: String, connection: NWConnection) {
        Task { @MainActor in
            self.lastRequest = request
        }

        // Parse HTTP request
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request"])
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request line"])
            return
        }

        let method = parts[0]
        let path = parts[1]

        // Extract body for POST requests
        var body: [String: Any]? = nil
        if method == "POST", let bodyStart = request.range(of: "\r\n\r\n") {
            let bodyString = String(request[bodyStart.upperBound...])
            if let bodyData = bodyString.data(using: .utf8) {
                body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            }
        }

        // Route request
        Task {
            await self.routeRequest(method: method, path: path, body: body, connection: connection)
        }
    }

    // MARK: - Routing

    private func routeRequest(method: String, path: String, body: [String: Any]?, connection: NWConnection) async {
        print("[TestAPIServer] \(method) \(path)")

        switch (method, path) {

        // Health check
        case ("GET", "/health"):
            sendResponse(connection: connection, status: 200, body: [
                "status": "ok",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ])

        // === SILENCE PROCESSOR ===

        case ("POST", "/api/silence/detect"):
            await handleDetectSilences(body: body, connection: connection)

        case ("POST", "/api/silence/crop"):
            await handleCropSilences(body: body, connection: connection)

        // === AUDIO COMPRESSOR ===

        case ("POST", "/api/audio/compress"):
            await handleCompress(body: body, connection: connection)

        case ("POST", "/api/audio/needs-compression"):
            await handleNeedsCompression(body: body, connection: connection)

        case ("POST", "/api/audio/estimate-size"):
            await handleEstimateSize(body: body, connection: connection)

        case ("POST", "/api/audio/duration"):
            await handleGetDuration(body: body, connection: connection)

        // === KEYCHAIN ===

        case ("GET", "/api/keychain/providers"):
            handleGetProviders(connection: connection)

        case ("POST", "/api/keychain/set"):
            handleSetKey(body: body, connection: connection)

        case ("POST", "/api/keychain/get"):
            handleGetKey(body: body, connection: connection)

        case ("POST", "/api/keychain/delete"):
            handleDeleteKey(body: body, connection: connection)

        // === TRANSCRIPTION ===

        case ("POST", "/api/transcribe"):
            await handleTranscribe(body: body, connection: connection)

        case ("GET", "/api/transcribe/models"):
            handleGetModels(connection: connection)

        case ("POST", "/api/transcribe/estimate-cost"):
            await handleEstimateCost(body: body, connection: connection)

        // === RECORDING ===

        case ("POST", "/api/recording/start"):
            await handleStartRecording(body: body, connection: connection)

        case ("POST", "/api/recording/stop"):
            await handleStopRecording(connection: connection)

        case ("GET", "/api/recording/status"):
            await handleRecordingStatus(connection: connection)

        // === MEETINGS ===

        case ("GET", "/api/meetings"):
            await handleGetMeetings(connection: connection)

        case ("POST", "/api/meetings/get"):
            await handleGetMeeting(body: body, connection: connection)

        default:
            sendResponse(connection: connection, status: 404, body: [
                "error": "Not found",
                "path": path,
                "available_endpoints": [
                    "GET /health",
                    "POST /api/silence/detect",
                    "POST /api/silence/crop",
                    "POST /api/audio/compress",
                    "POST /api/audio/needs-compression",
                    "POST /api/audio/estimate-size",
                    "POST /api/audio/duration",
                    "GET /api/keychain/providers",
                    "POST /api/keychain/set",
                    "POST /api/keychain/get",
                    "POST /api/keychain/delete",
                    "POST /api/transcribe",
                    "GET /api/transcribe/models",
                    "POST /api/transcribe/estimate-cost",
                    "POST /api/recording/start",
                    "POST /api/recording/stop",
                    "GET /api/recording/status",
                    "GET /api/meetings",
                    "POST /api/meetings/get"
                ]
            ])
        }
    }

    // MARK: - Silence Processor Handlers

    private func handleDetectSilences(body: [String: Any]?, connection: NWConnection) async {
        guard let audioPath = body?["audioPath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing audioPath"])
            return
        }

        let threshold = body?["threshold"] as? Float ?? -40
        let minDuration = body?["minDuration"] as? Double ?? 5.0

        do {
            let silences = try await SilenceProcessor.shared.detectSilences(
                audioPath: audioPath,
                threshold: threshold,
                minDuration: minDuration
            )

            let silenceData = silences.map { silence in
                [
                    "start": silence.start,
                    "end": silence.end,
                    "duration": silence.duration
                ]
            }

            sendResponse(connection: connection, status: 200, body: [
                "success": true,
                "count": silences.count,
                "silences": silenceData
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    private func handleCropSilences(body: [String: Any]?, connection: NWConnection) async {
        guard let audioPath = body?["audioPath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing audioPath"])
            return
        }

        let minSilenceDuration = body?["minSilenceDuration"] as? Double ?? 300
        let keepDuration = body?["keepDuration"] as? Double ?? 1.0

        do {
            let result = try await SilenceProcessor.shared.cropLongSilences(
                audioPath: audioPath,
                minSilenceDuration: minSilenceDuration,
                keepDuration: keepDuration
            )

            sendResponse(connection: connection, status: 200, body: [
                "success": true,
                "outputPath": result.outputPath,
                "originalDuration": result.originalDuration,
                "newDuration": result.newDuration,
                "silencesCropped": result.silencesCropped,
                "timeSaved": result.timeSaved
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    // MARK: - Audio Compressor Handlers

    private func handleCompress(body: [String: Any]?, connection: NWConnection) async {
        guard let inputPath = body?["inputPath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing inputPath"])
            return
        }

        let targetSize = body?["targetSizeBytes"] as? Int64 ?? AudioCompressor.targetSizeBytes
        let maxLevelRaw = body?["maxLevel"] as? Int ?? 1
        let maxLevel = CompressionLevel(rawValue: maxLevelRaw) ?? .aggressive

        do {
            let outputPath = try await AudioCompressor.shared.compress(
                inputPath: inputPath,
                targetSizeBytes: targetSize,
                maxLevel: maxLevel
            )

            let outputSize = await AudioCompressor.shared.getFileSize(filePath: outputPath)

            sendResponse(connection: connection, status: 200, body: [
                "success": true,
                "outputPath": outputPath,
                "outputSizeBytes": outputSize ?? 0
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    private func handleNeedsCompression(body: [String: Any]?, connection: NWConnection) async {
        guard let filePath = body?["filePath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing filePath"])
            return
        }

        let needsCompression = await AudioCompressor.shared.needsCompression(filePath: filePath)
        let fileSize = await AudioCompressor.shared.getFileSize(filePath: filePath)

        sendResponse(connection: connection, status: 200, body: [
            "needsCompression": needsCompression,
            "fileSizeBytes": fileSize ?? 0,
            "limitBytes": AudioCompressor.openAILimit
        ])
    }

    private func handleEstimateSize(body: [String: Any]?, connection: NWConnection) async {
        guard let inputPath = body?["inputPath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing inputPath"])
            return
        }

        let levelRaw = body?["level"] as? Int ?? 0
        let level = CompressionLevel(rawValue: levelRaw) ?? .standard

        let estimatedSize = await AudioCompressor.shared.estimateCompressedSize(inputPath: inputPath, level: level)

        sendResponse(connection: connection, status: 200, body: [
            "estimatedSizeBytes": estimatedSize,
            "level": level.rawValue,
            "levelName": level.displayName
        ])
    }

    private func handleGetDuration(body: [String: Any]?, connection: NWConnection) async {
        guard let filePath = body?["filePath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing filePath"])
            return
        }

        let duration = await AudioCompressor.shared.getAudioDuration(filePath: filePath)

        sendResponse(connection: connection, status: 200, body: [
            "durationSeconds": duration ?? 0,
            "durationFormatted": duration != nil ? formatDuration(duration!) : "unknown"
        ])
    }

    // MARK: - Keychain Handlers

    private func handleGetProviders(connection: NWConnection) {
        let configured = KeychainHelper.getAllConfiguredProviders()

        let providers = TranscriptionProvider.allCases.map { provider in
            [
                "id": provider.rawValue,
                "name": provider.displayName,
                "isConfigured": configured.contains(provider),
                "maxFileSize": provider.maxFileSizeFormatted,
                "maxDuration": provider.maxDurationFormatted
            ] as [String: Any]
        }

        sendResponse(connection: connection, status: 200, body: [
            "providers": providers,
            "configuredCount": configured.count
        ])
    }

    private func handleSetKey(body: [String: Any]?, connection: NWConnection) {
        guard let providerRaw = body?["provider"] as? String,
              let provider = TranscriptionProvider(rawValue: providerRaw),
              let key = body?["key"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing provider or key"])
            return
        }

        let success = KeychainHelper.saveKey(for: provider, key: key)

        sendResponse(connection: connection, status: success ? 200 : 500, body: [
            "success": success,
            "provider": provider.displayName
        ])
    }

    private func handleGetKey(body: [String: Any]?, connection: NWConnection) {
        guard let providerRaw = body?["provider"] as? String,
              let provider = TranscriptionProvider(rawValue: providerRaw) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing provider"])
            return
        }

        let hasKey = KeychainHelper.hasKey(for: provider)

        // Don't return actual key for security - just confirm it exists
        sendResponse(connection: connection, status: 200, body: [
            "provider": provider.displayName,
            "isConfigured": hasKey
        ])
    }

    private func handleDeleteKey(body: [String: Any]?, connection: NWConnection) {
        guard let providerRaw = body?["provider"] as? String,
              let provider = TranscriptionProvider(rawValue: providerRaw) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing provider"])
            return
        }

        let success = KeychainHelper.deleteKey(for: provider)

        sendResponse(connection: connection, status: success ? 200 : 500, body: [
            "success": success,
            "provider": provider.displayName
        ])
    }

    // MARK: - Transcription Handlers

    private func handleTranscribe(body: [String: Any]?, connection: NWConnection) async {
        guard let audioPath = body?["audioPath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing audioPath"])
            return
        }

        do {
            let result = try await TranscriptionService.shared.transcribe(audioPath: audioPath)

            sendResponse(connection: connection, status: 200, body: [
                "success": true,
                "text": result.text,
                "duration": result.duration,
                "costCents": result.costCents,
                "model": result.model.rawValue,
                "speakerCount": result.speakerCount ?? 0
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    private func handleGetModels(connection: NWConnection) {
        let allModels = TranscriptionModelOption.allModels.map { model in
            [
                "id": model.id,
                "fullId": model.fullId,
                "displayName": model.displayName,
                "costPerMinute": model.costPerMinute,
                "formattedCost": model.formattedCost,
                "provider": model.provider.displayName,
                "isConfigured": model.provider.isConfigured
            ] as [String: Any]
        }

        sendResponse(connection: connection, status: 200, body: [
            "models": allModels,
            "configuredModels": TranscriptionModelOption.configuredModels.map { $0.fullId }
        ])
    }

    private func handleEstimateCost(body: [String: Any]?, connection: NWConnection) async {
        guard let audioPath = body?["audioPath"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing audioPath"])
            return
        }

        do {
            let costCents = try await TranscriptionService.shared.estimateCost(audioPath: audioPath)
            let duration = await AudioCompressor.shared.getAudioDuration(filePath: audioPath)

            sendResponse(connection: connection, status: 200, body: [
                "costCents": costCents,
                "costDollars": Double(costCents) / 100.0,
                "durationSeconds": duration ?? 0
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    // MARK: - Recording Handlers

    private func handleStartRecording(body: [String: Any]?, connection: NWConnection) async {
        let title = body?["title"] as? String
        let sourceApp = body?["sourceApp"] as? String

        do {
            try await AudioCaptureManager.shared.startRecording(title: title, sourceApp: sourceApp)

            sendResponse(connection: connection, status: 200, body: [
                "success": true,
                "message": "Recording started"
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    private func handleStopRecording(connection: NWConnection) async {
        do {
            let url = try await AudioCaptureManager.shared.stopRecording()

            sendResponse(connection: connection, status: 200, body: [
                "success": true,
                "audioPath": url.path
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    private func handleRecordingStatus(connection: NWConnection) async {
        let manager = AudioCaptureManager.shared

        sendResponse(connection: connection, status: 200, body: [
            "isRecording": manager.isRecording,
            "duration": manager.currentDuration,
            "state": String(describing: manager.state)
        ])
    }

    // MARK: - Meetings Handlers

    private func handleGetMeetings(connection: NWConnection) async {
        do {
            let meetings = try await DatabaseManager.shared.getAllMeetings()

            let meetingsData = meetings.map { meeting in
                [
                    "id": meeting.id.uuidString,
                    "title": meeting.title,
                    "startTime": ISO8601DateFormatter().string(from: meeting.startTime),
                    "duration": meeting.duration ?? 0,
                    "status": meeting.status.rawValue,
                    "hasTranscript": meeting.transcript != nil
                ] as [String: Any]
            }

            sendResponse(connection: connection, status: 200, body: [
                "meetings": meetingsData,
                "count": meetings.count
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    private func handleGetMeeting(body: [String: Any]?, connection: NWConnection) async {
        guard let idString = body?["id"] as? String,
              let id = UUID(uuidString: idString) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing or invalid id"])
            return
        }

        do {
            guard let meeting = try await DatabaseManager.shared.getMeeting(id: id) else {
                sendResponse(connection: connection, status: 404, body: ["error": "Meeting not found"])
                return
            }

            sendResponse(connection: connection, status: 200, body: [
                "id": meeting.id.uuidString,
                "title": meeting.title,
                "startTime": ISO8601DateFormatter().string(from: meeting.startTime),
                "endTime": meeting.endTime != nil ? ISO8601DateFormatter().string(from: meeting.endTime!) : nil,
                "duration": meeting.duration ?? 0,
                "status": meeting.status.rawValue,
                "audioPath": meeting.audioPath,
                "transcript": meeting.transcript ?? "",
                "speakerCount": meeting.speakerCount ?? 0,
                "apiCostCents": meeting.apiCostCents ?? 0
            ])
        } catch {
            sendResponse(connection: connection, status: 500, body: [
                "error": error.localizedDescription
            ])
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, status: Int, body: [String: Any]) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let response = """
            HTTP/1.1 \(status) \(statusText)\r
            Content-Type: application/json\r
            Content-Length: \(jsonData.count)\r
            Access-Control-Allow-Origin: *\r
            Connection: close\r
            \r
            \(jsonString)
            """

            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Debug Menu Integration

#if DEBUG
extension TestAPIServer {
    /// Check if test API should be enabled (via env var or user default)
    static var shouldAutoStart: Bool {
        ProcessInfo.processInfo.environment["ENABLE_TEST_API"] == "1" ||
        UserDefaults.standard.bool(forKey: "enableTestAPI")
    }
}
#endif
