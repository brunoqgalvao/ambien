//
//  main.swift
//  ambient
//
//  Command-line interface for Ambient meeting recorder.
//  Reads from ~/.ambient/meetings/ JSON files.
//

import Foundation

// MARK: - Models

struct AgentIndex: Codable {
    let version: Int
    let lastUpdated: String
    var meetings: [AgentMeetingIndex]
    var groups: [AgentGroupIndex]?
}

struct AgentMeetingIndex: Codable {
    let id: String
    let date: String
    let title: String
    let status: String
    let path: String
}

struct AgentGroupIndex: Codable {
    let id: String
    let name: String
    let emoji: String?
    let meetingCount: Int
    let path: String
}

struct AgentMeeting: Codable {
    let id: String
    let title: String
    let date: String
    let startTime: String
    let endTime: String?
    let duration: Int
    let sourceApp: String?
    let transcript: String?
    let actionItems: [String]?
    let status: String
    let audioPath: String
    let apiCostCents: Int?
    let createdAt: String
}

// MARK: - Paths

let homeDir = FileManager.default.homeDirectoryForCurrentUser
let baseDir = homeDir.appendingPathComponent(".ambient/meetings")
let indexPath = baseDir.appendingPathComponent("index.json")

// MARK: - Helpers

func printError(_ message: String) {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
}

func loadIndex() -> AgentIndex? {
    guard let data = try? Data(contentsOf: indexPath) else {
        printError("Cannot read index at \(indexPath.path)")
        printError("Is Ambient running? Have you recorded any meetings?")
        return nil
    }

    guard let index = try? JSONDecoder().decode(AgentIndex.self, from: data) else {
        printError("Cannot parse index.json")
        return nil
    }

    return index
}

func loadMeeting(path: String) -> AgentMeeting? {
    let fullPath = baseDir.appendingPathComponent(path)
    guard let data = try? Data(contentsOf: fullPath) else {
        return nil
    }
    return try? JSONDecoder().decode(AgentMeeting.self, from: data)
}

func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Commands

func showHelp() {
    print("""
    ambient - CLI for Ambient meeting recorder

    USAGE:
        ambient <command> [options]

    COMMANDS:
        list              List recent meetings
        search <query>    Search transcripts for a keyword
        get <id>          Get a specific meeting by ID
        export <id>       Export meeting to stdout
        groups            List meeting groups
        help              Show this help

    OPTIONS:
        --date <YYYY-MM-DD>   Filter by date (list command)
        --limit <n>           Limit results (default: 10)
        --format <fmt>        Output format: json, md, txt (export command)
        --json                Output as JSON (list, search, get commands)

    EXAMPLES:
        ambient list
        ambient list --date 2025-01-15
        ambient search "authentication"
        ambient get abc123
        ambient export abc123 --format=md
    """)
}

func listMeetings(date: String?, limit: Int, asJson: Bool) {
    guard let index = loadIndex() else { return }

    var meetings = index.meetings.filter { $0.status == "ready" }

    // Filter by date if specified
    if let date = date {
        meetings = meetings.filter { $0.date == date }
    }

    // Sort by date descending
    meetings.sort { $0.date > $1.date }

    // Limit results
    let limited = Array(meetings.prefix(limit))

    if asJson {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(limited),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
    }

    if limited.isEmpty {
        print("No meetings found.")
        return
    }

    print("MEETINGS (\(limited.count) of \(meetings.count))\n")

    for meeting in limited {
        print("\(meeting.date)  \(meeting.title)")
        print("  ID: \(meeting.id.prefix(8))...")
        print("")
    }
}

func searchMeetings(query: String, limit: Int, asJson: Bool) {
    guard let index = loadIndex() else { return }

    let readyMeetings = index.meetings.filter { $0.status == "ready" }
    var results: [(meeting: AgentMeeting, snippet: String)] = []

    let lowercaseQuery = query.lowercased()

    for entry in readyMeetings {
        guard let meeting = loadMeeting(path: entry.path) else { continue }
        guard let transcript = meeting.transcript?.lowercased() else { continue }

        if transcript.contains(lowercaseQuery) {
            // Extract snippet around match
            if let range = transcript.range(of: lowercaseQuery) {
                let start = transcript.index(range.lowerBound, offsetBy: -50, limitedBy: transcript.startIndex) ?? transcript.startIndex
                let end = transcript.index(range.upperBound, offsetBy: 50, limitedBy: transcript.endIndex) ?? transcript.endIndex
                var snippet = String(transcript[start..<end])
                snippet = snippet.replacingOccurrences(of: "\n", with: " ")
                results.append((meeting, "...\(snippet)..."))
            }
        }

        if results.count >= limit { break }
    }

    if asJson {
        let jsonResults = results.map { ["id": $0.meeting.id, "title": $0.meeting.title, "date": $0.meeting.date, "snippet": $0.snippet] }
        if let data = try? JSONSerialization.data(withJSONObject: jsonResults, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
    }

    if results.isEmpty {
        print("No matches found for '\(query)'")
        return
    }

    print("SEARCH RESULTS for '\(query)' (\(results.count) matches)\n")

    for (meeting, snippet) in results {
        print("\(meeting.date)  \(meeting.title)")
        print("  \(snippet)")
        print("  ID: \(meeting.id.prefix(8))...")
        print("")
    }
}

func getMeeting(idPrefix: String, asJson: Bool) {
    guard let index = loadIndex() else { return }

    let lowerId = idPrefix.lowercased()
    guard let entry = index.meetings.first(where: { $0.id.lowercased().hasPrefix(lowerId) }) else {
        printError("Meeting not found: \(idPrefix)")
        return
    }

    guard let meeting = loadMeeting(path: entry.path) else {
        printError("Cannot read meeting file: \(entry.path)")
        return
    }

    if asJson {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(meeting),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
    }

    print("MEETING: \(meeting.title)")
    print("Date: \(meeting.date) \(meeting.startTime)")
    print("Duration: \(formatDuration(meeting.duration))")
    if let source = meeting.sourceApp {
        print("Source: \(source)")
    }
    print("ID: \(meeting.id)")
    print("")

    if let items = meeting.actionItems, !items.isEmpty {
        print("ACTION ITEMS:")
        for item in items {
            print("  - \(item)")
        }
        print("")
    }

    if let transcript = meeting.transcript {
        print("TRANSCRIPT:")
        print(transcript)
    }
}

func exportMeeting(idPrefix: String, format: String) {
    guard let index = loadIndex() else { return }

    let lowerId = idPrefix.lowercased()
    guard let entry = index.meetings.first(where: { $0.id.lowercased().hasPrefix(lowerId) }) else {
        printError("Meeting not found: \(idPrefix)")
        return
    }

    guard let meeting = loadMeeting(path: entry.path) else {
        printError("Cannot read meeting file: \(entry.path)")
        return
    }

    switch format {
    case "json":
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(meeting),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }

    case "md", "markdown":
        print("# \(meeting.title)")
        print("")
        print("**Date:** \(meeting.date) \(meeting.startTime)")
        print("**Duration:** \(formatDuration(meeting.duration))")
        if let source = meeting.sourceApp {
            print("**Source:** \(source)")
        }
        print("")

        if let items = meeting.actionItems, !items.isEmpty {
            print("## Action Items")
            print("")
            for item in items {
                print("- \(item)")
            }
            print("")
        }

        if let transcript = meeting.transcript {
            print("## Transcript")
            print("")
            print(transcript)
        }

    case "txt", "text":
        print(meeting.title.uppercased())
        print(String(repeating: "=", count: meeting.title.count))
        print("")
        print("Date: \(meeting.date) \(meeting.startTime)")
        print("Duration: \(formatDuration(meeting.duration))")
        print("")

        if let transcript = meeting.transcript {
            print(transcript)
        }

    default:
        printError("Unknown format: \(format). Use: json, md, txt")
    }
}

func listGroups(asJson: Bool) {
    guard let index = loadIndex() else { return }

    guard let groups = index.groups, !groups.isEmpty else {
        print("No groups found.")
        return
    }

    if asJson {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(groups),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
    }

    print("GROUPS (\(groups.count))\n")

    for group in groups {
        let emoji = group.emoji ?? ""
        print("\(emoji) \(group.name) (\(group.meetingCount) meetings)")
        print("  ID: \(group.id.prefix(8))...")
        print("")
    }
}

// MARK: - Argument Parsing

func parseArgs() {
    let args = CommandLine.arguments

    if args.count < 2 {
        showHelp()
        return
    }

    let command = args[1]
    var date: String?
    var limit = 10
    var format = "txt"
    var asJson = false
    var query: String?
    var id: String?

    // Parse remaining args
    var i = 2
    while i < args.count {
        let arg = args[i]

        switch arg {
        case "--date":
            if i + 1 < args.count {
                date = args[i + 1]
                i += 1
            }
        case "--limit":
            if i + 1 < args.count, let n = Int(args[i + 1]) {
                limit = n
                i += 1
            }
        case "--format":
            if i + 1 < args.count {
                format = args[i + 1]
                i += 1
            }
        case "--json":
            asJson = true
        default:
            if arg.hasPrefix("--format=") {
                format = String(arg.dropFirst(9))
            } else if query == nil && command == "search" {
                query = arg
            } else if id == nil && (command == "get" || command == "export") {
                id = arg
            }
        }
        i += 1
    }

    // Execute command
    switch command {
    case "list", "ls":
        listMeetings(date: date, limit: limit, asJson: asJson)

    case "search", "find":
        guard let q = query else {
            printError("Usage: ambient search <query>")
            exit(1)
        }
        searchMeetings(query: q, limit: limit, asJson: asJson)

    case "get", "show":
        guard let meetingId = id else {
            printError("Usage: ambient get <meeting-id>")
            exit(1)
        }
        getMeeting(idPrefix: meetingId, asJson: asJson)

    case "export":
        guard let meetingId = id else {
            printError("Usage: ambient export <meeting-id> [--format=json|md|txt]")
            exit(1)
        }
        exportMeeting(idPrefix: meetingId, format: format)

    case "groups":
        listGroups(asJson: asJson)

    case "help", "--help", "-h":
        showHelp()

    case "version", "--version", "-v":
        print("ambient 1.0.0")

    default:
        printError("Unknown command: \(command)")
        print("Run 'ambient help' for usage.")
        exit(1)
    }
}

// MARK: - Main

parseArgs()
