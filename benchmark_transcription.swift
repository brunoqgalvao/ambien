#!/usr/bin/env swift

//
//  benchmark_transcription.swift
//  Transcription Provider Benchmark
//
//  Benchmarks different transcription APIs (OpenAI, Gemini, AssemblyAI, Deepgram)
//  on your audio files and outputs a comparison report.
//
//  Usage:
//    chmod +x benchmark_transcription.swift
//    ./benchmark_transcription.swift /path/to/audio1.m4a /path/to/audio2.mp3
//
//  Environment variables (set via export or .env):
//    OPENAI_API_KEY      - OpenAI API key
//    GEMINI_API_KEY      - Google Gemini API key
//    ASSEMBLYAI_API_KEY  - AssemblyAI API key
//    DEEPGRAM_API_KEY    - Deepgram API key
//

import Foundation

// MARK: - Configuration

struct BenchmarkConfig {
    static let providers: [TranscriptionProvider] = [
        .openaiWhisper,
        .openaiGPT4oMini,
        .geminiFlash,
        .assemblyAI,
        .deepgram
    ]

    /// Max concurrent requests per provider (to avoid rate limits)
    static let maxConcurrent = 1

    /// Timeout per request in seconds
    static let timeoutSeconds: Double = 300
}

// MARK: - Provider Definitions

enum TranscriptionProvider: String, CaseIterable {
    case openaiWhisper = "openai-whisper"
    case openaiGPT4oMini = "openai-gpt4o-mini"
    case geminiFlash = "gemini-flash"
    case assemblyAI = "assemblyai"
    case deepgram = "deepgram"

    var displayName: String {
        switch self {
        case .openaiWhisper: return "OpenAI Whisper"
        case .openaiGPT4oMini: return "OpenAI GPT-4o Mini Transcribe"
        case .geminiFlash: return "Gemini 2.0 Flash"
        case .assemblyAI: return "AssemblyAI"
        case .deepgram: return "Deepgram Nova-3"
        }
    }

    var model: String {
        switch self {
        case .openaiWhisper: return "whisper-1"
        case .openaiGPT4oMini: return "gpt-4o-mini-transcribe"
        case .geminiFlash: return "gemini-2.0-flash"
        case .assemblyAI: return "universal"
        case .deepgram: return "nova-3"
        }
    }

    var costPerMinute: Double {
        switch self {
        case .openaiWhisper: return 0.006
        case .openaiGPT4oMini: return 0.003
        case .geminiFlash: return 0.0002  // Estimated based on token pricing
        case .assemblyAI: return 0.0025
        case .deepgram: return 0.0043
        }
    }

    var envVar: String {
        switch self {
        case .openaiWhisper, .openaiGPT4oMini: return "OPENAI_API_KEY"
        case .geminiFlash: return "GEMINI_API_KEY"
        case .assemblyAI: return "ASSEMBLYAI_API_KEY"
        case .deepgram: return "DEEPGRAM_API_KEY"
        }
    }

    var maxFileSize: Int64 {
        switch self {
        case .openaiWhisper, .openaiGPT4oMini: return 25 * 1024 * 1024  // 25MB
        case .geminiFlash: return 20 * 1024 * 1024  // 20MB for inline
        case .assemblyAI: return 5 * 1024 * 1024 * 1024  // 5GB
        case .deepgram: return 2 * 1024 * 1024 * 1024  // 2GB
        }
    }

    func apiKey() -> String? {
        ProcessInfo.processInfo.environment[envVar]
    }

    var isConfigured: Bool {
        apiKey() != nil && !apiKey()!.isEmpty
    }
}

// MARK: - Result Types

struct TranscriptionResult {
    let provider: TranscriptionProvider
    let audioFile: String
    let transcript: String
    let latencySeconds: Double
    let durationSeconds: Double?  // Audio duration if available
    let estimatedCost: Double
    let wordCount: Int
    let error: String?

    var wordsPerSecond: Double? {
        guard latencySeconds > 0 else { return nil }
        return Double(wordCount) / latencySeconds
    }
}

struct BenchmarkReport {
    let results: [TranscriptionResult]
    let timestamp: Date

    func printReport() {
        print("\n" + String(repeating: "=", count: 80))
        print("TRANSCRIPTION BENCHMARK REPORT")
        print("Generated: \(ISO8601DateFormatter().string(from: timestamp))")
        print(String(repeating: "=", count: 80) + "\n")

        // Group by audio file
        let byFile = Dictionary(grouping: results, by: { $0.audioFile })

        for (file, fileResults) in byFile.sorted(by: { $0.key < $1.key }) {
            let filename = (file as NSString).lastPathComponent
            print("📁 \(filename)")
            print(String(repeating: "-", count: 60))

            // Sort by latency (fastest first)
            let sorted = fileResults.sorted { $0.latencySeconds < $1.latencySeconds }

            for (index, result) in sorted.enumerated() {
                let medal = index == 0 ? "🥇" : (index == 1 ? "🥈" : (index == 2 ? "🥉" : "  "))
                let errorFlag = result.error != nil ? "❌" : "✅"

                if let error = result.error {
                    print("\(medal) \(result.provider.displayName.padding(toLength: 28, withPad: " ", startingAt: 0)) \(errorFlag) Error: \(error)")
                } else {
                    let latency = String(format: "%.2fs", result.latencySeconds)
                    let cost = String(format: "$%.4f", result.estimatedCost)
                    let words = "\(result.wordCount) words"
                    print("\(medal) \(result.provider.displayName.padding(toLength: 28, withPad: " ", startingAt: 0)) \(errorFlag) \(latency.padding(toLength: 10, withPad: " ", startingAt: 0)) \(cost.padding(toLength: 10, withPad: " ", startingAt: 0)) \(words)")
                }
            }
            print()
        }

        // Summary statistics
        let successful = results.filter { $0.error == nil }
        if !successful.isEmpty {
            print(String(repeating: "=", count: 80))
            print("SUMMARY")
            print(String(repeating: "-", count: 60))

            // Average latency by provider
            let byProvider = Dictionary(grouping: successful, by: { $0.provider })

            print("\nAverage Performance by Provider:")
            for provider in TranscriptionProvider.allCases {
                guard let providerResults = byProvider[provider], !providerResults.isEmpty else { continue }

                let avgLatency = providerResults.map { $0.latencySeconds }.reduce(0, +) / Double(providerResults.count)
                let avgCost = providerResults.map { $0.estimatedCost }.reduce(0, +) / Double(providerResults.count)
                let avgWords = providerResults.map { $0.wordCount }.reduce(0, +) / providerResults.count

                print("  \(provider.displayName.padding(toLength: 28, withPad: " ", startingAt: 0)) Avg: \(String(format: "%.2fs", avgLatency).padding(toLength: 10, withPad: " ", startingAt: 0)) \(String(format: "$%.4f", avgCost).padding(toLength: 10, withPad: " ", startingAt: 0)) ~\(avgWords) words")
            }
        }

        // Transcript comparison hint
        print("\n💡 TIP: Compare transcripts in the generated JSON file for quality evaluation")
        print(String(repeating: "=", count: 80))
    }

    func saveJSON(to path: String) throws {
        struct JSONResult: Codable {
            let provider: String
            let model: String
            let audioFile: String
            let transcript: String
            let latencySeconds: Double
            let estimatedCost: Double
            let wordCount: Int
            let error: String?
        }

        let jsonResults = results.map { r in
            JSONResult(
                provider: r.provider.rawValue,
                model: r.provider.model,
                audioFile: r.audioFile,
                transcript: r.transcript,
                latencySeconds: r.latencySeconds,
                estimatedCost: r.estimatedCost,
                wordCount: r.wordCount,
                error: r.error
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jsonResults)
        try data.write(to: URL(fileURLWithPath: path))
        print("📄 Results saved to: \(path)")
    }
}

// MARK: - Transcription Implementations

actor TranscriptionBenchmark {

    // MARK: - OpenAI

    func transcribeOpenAI(audioPath: String, model: String, apiKey: String) async throws -> (text: String, duration: Double?) {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = BenchmarkConfig.timeoutSeconds

        var body = Data()

        // File field
        let ext = fileURL.pathExtension.lowercased()
        let mimeType = ext == "mp3" ? "audio/mpeg" : (ext == "wav" ? "audio/wav" : "audio/m4a")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        struct OpenAIResponse: Codable {
            let text: String
            let duration: Double?
        }

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return (result.text, result.duration)
    }

    // MARK: - Gemini

    func transcribeGemini(audioPath: String, apiKey: String) async throws -> String {
        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)
        let base64Audio = audioData.base64EncodedString()

        let ext = fileURL.pathExtension.lowercased()
        let mimeType = ext == "mp3" ? "audio/mpeg" : (ext == "wav" ? "audio/wav" : "audio/mp4")

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = BenchmarkConfig.timeoutSeconds

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64Audio
                            ]
                        ],
                        [
                            "text": "Transcribe this audio exactly. Return only the transcription text, nothing else."
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 8192
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Gemini", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "Gemini", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        return text
    }

    // MARK: - AssemblyAI

    func transcribeAssemblyAI(audioPath: String, apiKey: String) async throws -> String {
        // Step 1: Upload the file
        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)

        let uploadURL = URL(string: "https://api.assemblyai.com/v2/upload")!
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = audioData
        uploadRequest.timeoutInterval = BenchmarkConfig.timeoutSeconds

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)

        guard let uploadHttpResponse = uploadResponse as? HTTPURLResponse,
              uploadHttpResponse.statusCode == 200 else {
            throw NSError(domain: "AssemblyAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }

        guard let uploadJson = try JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let uploadUrl = uploadJson["upload_url"] as? String else {
            throw NSError(domain: "AssemblyAI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to get upload URL"])
        }

        // Step 2: Create transcription
        let transcriptURL = URL(string: "https://api.assemblyai.com/v2/transcript")!
        var transcriptRequest = URLRequest(url: transcriptURL)
        transcriptRequest.httpMethod = "POST"
        transcriptRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
        transcriptRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        transcriptRequest.httpBody = try JSONSerialization.data(withJSONObject: ["audio_url": uploadUrl])

        let (transcriptData, _) = try await URLSession.shared.data(for: transcriptRequest)

        guard let transcriptJson = try JSONSerialization.jsonObject(with: transcriptData) as? [String: Any],
              let transcriptId = transcriptJson["id"] as? String else {
            throw NSError(domain: "AssemblyAI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create transcript"])
        }

        // Step 3: Poll for completion
        let pollURL = URL(string: "https://api.assemblyai.com/v2/transcript/\(transcriptId)")!
        var pollRequest = URLRequest(url: pollURL)
        pollRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")

        while true {
            try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

            let (pollData, _) = try await URLSession.shared.data(for: pollRequest)
            guard let pollJson = try JSONSerialization.jsonObject(with: pollData) as? [String: Any],
                  let status = pollJson["status"] as? String else {
                continue
            }

            if status == "completed" {
                return pollJson["text"] as? String ?? ""
            } else if status == "error" {
                throw NSError(domain: "AssemblyAI", code: -4, userInfo: [NSLocalizedDescriptionKey: pollJson["error"] as? String ?? "Unknown error"])
            }
        }
    }

    // MARK: - Deepgram

    func transcribeDeepgram(audioPath: String, apiKey: String) async throws -> String {
        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)

        let ext = fileURL.pathExtension.lowercased()
        let mimeType = ext == "mp3" ? "audio/mpeg" : (ext == "wav" ? "audio/wav" : "audio/mp4")

        let url = URL(string: "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = BenchmarkConfig.timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Deepgram", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Deepgram", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            throw NSError(domain: "Deepgram", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        return transcript
    }

    // MARK: - Main Benchmark

    func benchmark(provider: TranscriptionProvider, audioPath: String) async -> TranscriptionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var transcript = ""
        var duration: Double? = nil
        var error: String? = nil

        do {
            guard let apiKey = provider.apiKey() else {
                throw NSError(domain: provider.rawValue, code: -1, userInfo: [NSLocalizedDescriptionKey: "API key not configured"])
            }

            // Check file size
            let attrs = try FileManager.default.attributesOfItem(atPath: audioPath)
            let fileSize = attrs[.size] as? Int64 ?? 0

            if fileSize > provider.maxFileSize {
                throw NSError(domain: provider.rawValue, code: -2, userInfo: [NSLocalizedDescriptionKey: "File too large (\(fileSize / 1_000_000)MB > \(provider.maxFileSize / 1_000_000)MB)"])
            }

            switch provider {
            case .openaiWhisper:
                let result = try await transcribeOpenAI(audioPath: audioPath, model: "whisper-1", apiKey: apiKey)
                transcript = result.text
                duration = result.duration

            case .openaiGPT4oMini:
                let result = try await transcribeOpenAI(audioPath: audioPath, model: "gpt-4o-mini-transcribe", apiKey: apiKey)
                transcript = result.text
                duration = result.duration

            case .geminiFlash:
                transcript = try await transcribeGemini(audioPath: audioPath, apiKey: apiKey)

            case .assemblyAI:
                transcript = try await transcribeAssemblyAI(audioPath: audioPath, apiKey: apiKey)

            case .deepgram:
                transcript = try await transcribeDeepgram(audioPath: audioPath, apiKey: apiKey)
            }

        } catch {
            let nsError = error as NSError
            self.error = nsError.localizedDescription
        }

        let latency = CFAbsoluteTimeGetCurrent() - startTime
        let wordCount = transcript.split(separator: " ").count

        // Estimate cost based on duration (rough: assume 1 min if not provided)
        let estimatedDuration = duration ?? 60.0
        let estimatedCost = (estimatedDuration / 60.0) * provider.costPerMinute

        return TranscriptionResult(
            provider: provider,
            audioFile: audioPath,
            transcript: transcript,
            latencySeconds: latency,
            durationSeconds: duration,
            estimatedCost: estimatedCost,
            wordCount: wordCount,
            error: error
        )
    }
}

// MARK: - Main

func printUsage() {
    print("""

    📊 Transcription Provider Benchmark

    Usage: ./benchmark_transcription.swift <audio_file1> [audio_file2] ...

    Environment Variables (set at least one):
      OPENAI_API_KEY      - For OpenAI Whisper and GPT-4o Mini
      GEMINI_API_KEY      - For Google Gemini Flash
      ASSEMBLYAI_API_KEY  - For AssemblyAI
      DEEPGRAM_API_KEY    - For Deepgram Nova-3

    Example:
      export OPENAI_API_KEY="sk-..."
      export GEMINI_API_KEY="AIza..."
      ./benchmark_transcription.swift meeting1.m4a meeting2.mp3

    Supported formats: .m4a, .mp3, .wav

    """)
}

func main() async {
    let args = CommandLine.arguments

    if args.count < 2 {
        printUsage()
        exit(1)
    }

    let audioFiles = Array(args.dropFirst())

    // Validate files exist
    for file in audioFiles {
        guard FileManager.default.fileExists(atPath: file) else {
            print("❌ File not found: \(file)")
            exit(1)
        }
    }

    // Check which providers are configured
    let configuredProviders = BenchmarkConfig.providers.filter { $0.isConfigured }

    if configuredProviders.isEmpty {
        print("❌ No API keys configured. Set at least one of:")
        for provider in TranscriptionProvider.allCases {
            print("   export \(provider.envVar)=\"your-key\"")
        }
        exit(1)
    }

    print("🚀 Starting benchmark with \(configuredProviders.count) providers on \(audioFiles.count) file(s)")
    print("   Providers: \(configuredProviders.map { $0.displayName }.joined(separator: ", "))")
    print()

    let benchmark = TranscriptionBenchmark()
    var results: [TranscriptionResult] = []

    for audioFile in audioFiles {
        let filename = (audioFile as NSString).lastPathComponent
        print("📁 Processing: \(filename)")

        for provider in configuredProviders {
            print("   ⏳ \(provider.displayName)...", terminator: "")
            fflush(stdout)

            let result = await benchmark.benchmark(provider: provider, audioPath: audioFile)
            results.append(result)

            if let error = result.error {
                print(" ❌ \(error)")
            } else {
                print(" ✅ \(String(format: "%.2fs", result.latencySeconds)) (\(result.wordCount) words)")
            }
        }
        print()
    }

    // Generate report
    let report = BenchmarkReport(results: results, timestamp: Date())
    report.printReport()

    // Save JSON
    let jsonPath = "benchmark_results_\(Int(Date().timeIntervalSince1970)).json"
    do {
        try report.saveJSON(to: jsonPath)
    } catch {
        print("⚠️ Failed to save JSON: \(error)")
    }
}

// Run
Task {
    await main()
    exit(0)
}

// Keep the script running
RunLoop.main.run()
