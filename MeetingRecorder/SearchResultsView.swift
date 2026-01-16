//
//  SearchResultsView.swift
//  MeetingRecorder
//
//  Search results overlay with highlighted snippets from transcripts
//

import SwiftUI

/// Search results overlay shown when searching across all meetings
struct SearchResultsView: View {
    let searchText: String
    let results: [Meeting]
    let onSelect: (Meeting) -> Void
    let onClose: () -> Void

    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            SearchResultsHeader(
                query: searchText,
                resultCount: results.count,
                onClose: onClose
            )

            Divider()

            // Results list
            if results.isEmpty {
                NoSearchResults(query: searchText)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, meeting in
                                SearchResultRow(
                                    meeting: meeting,
                                    searchText: searchText,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    onSelect(meeting)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Keyboard hints
            SearchKeyboardHints()
        }
        .background(Color(.windowBackgroundColor))
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.upArrow) {
            selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectNext()
            return .handled
        }
        .onKeyPress("k") {
            selectPrevious()
            return .handled
        }
        .onKeyPress("j") {
            selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            if !results.isEmpty && selectedIndex < results.count {
                onSelect(results[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private func selectNext() {
        guard !results.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, results.count - 1)
    }

    private func selectPrevious() {
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }
}

// MARK: - Search Results Header

struct SearchResultsHeader: View {
    let query: String
    let resultCount: Int
    let onClose: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            Text("\(resultCount) result\(resultCount == 1 ? "" : "s") for \"\(query)\"")
                .font(.subheadline.weight(.medium))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close search (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let meeting: Meeting
    let searchText: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with title and date
            HStack {
                Text(meeting.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(formattedDateTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Snippet with highlighted search term
            if let snippet = extractSnippet() {
                HighlightedText(text: snippet, highlight: searchText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Source app badge
            if let app = meeting.sourceApp {
                HStack {
                    Image(systemName: sourceAppIcon(app))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(app)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.brandViolet.opacity(0.1) : Color.brandCreamDark.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.brandViolet.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    private var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: meeting.startTime)
    }

    private func extractSnippet() -> String? {
        guard let transcript = meeting.transcript else { return nil }

        let lowercasedTranscript = transcript.lowercased()
        let lowercasedSearch = searchText.lowercased()

        if let range = lowercasedTranscript.range(of: lowercasedSearch) {
            let startDistance = lowercasedTranscript.distance(from: lowercasedTranscript.startIndex, to: range.lowerBound)
            let snippetStart = max(0, startDistance - 50)
            let snippetEnd = min(transcript.count, startDistance + searchText.count + 100)

            let startIndex = transcript.index(transcript.startIndex, offsetBy: snippetStart)
            let endIndex = transcript.index(transcript.startIndex, offsetBy: snippetEnd)

            var snippet = String(transcript[startIndex..<endIndex])

            // Add ellipsis if truncated
            if snippetStart > 0 {
                snippet = "..." + snippet
            }
            if snippetEnd < transcript.count {
                snippet = snippet + "..."
            }

            return snippet
        }

        // Fallback: return first 150 characters
        return String(transcript.prefix(150)) + (transcript.count > 150 ? "..." : "")
    }

    private func sourceAppIcon(_ app: String) -> String {
        switch app.lowercased() {
        case "zoom":
            return "video.fill"
        case "google meet":
            return "person.2.fill"
        case "microsoft teams":
            return "person.3.fill"
        case "slack":
            return "number"
        case "facetime":
            return "video.fill"
        default:
            return "app.fill"
        }
    }
}

// MARK: - Highlighted Text

struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        // Split text and highlight matches
        let attributedString = createAttributedString()
        Text(attributedString)
    }

    private func createAttributedString() -> AttributedString {
        var result = AttributedString(text)
        let lowercasedText = text.lowercased()
        let lowercasedHighlight = highlight.lowercased()

        var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

        while let range = lowercasedText.range(of: lowercasedHighlight, range: searchRange) {
            let startOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
            let length = lowercasedHighlight.count

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(attrStart, offsetByCharacters: length)
            result[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.3)
            result[attrStart..<attrEnd].foregroundColor = .primary

            searchRange = range.upperBound..<lowercasedText.endIndex
        }

        return result
    }
}

// MARK: - No Results

struct NoSearchResults: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No results for \"\(query)\"")
                .font(.headline)

            Text("Try different keywords or check spelling")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Keyboard Hints

struct SearchKeyboardHints: View {
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 4) {
                Text("↑/↓")
                    .font(.caption.weight(.medium).monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.brandCreamDark)
                    .cornerRadius(3)
                Text("navigate")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Text("↵")
                    .font(.caption.weight(.medium).monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.brandCreamDark)
                    .cornerRadius(3)
                Text("open meeting")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Text("Esc")
                    .font(.caption.weight(.medium).monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.brandCreamDark)
                    .cornerRadius(3)
                Text("close search")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews

#Preview("Search Results") {
    SearchResultsView(
        searchText: "pricing",
        results: Meeting.sampleMeetings,
        onSelect: { _ in },
        onClose: {}
    )
    .frame(width: 600, height: 500)
}

#Preview("Search Results - No Results") {
    SearchResultsView(
        searchText: "nonexistent query",
        results: [],
        onSelect: { _ in },
        onClose: {}
    )
    .frame(width: 600, height: 500)
}

#Preview("Search Result Row") {
    VStack(spacing: 12) {
        SearchResultRow(
            meeting: Meeting.sampleMeetings[0],
            searchText: "standup",
            isSelected: true
        )
        SearchResultRow(
            meeting: Meeting.sampleMeetings[2],
            searchText: "career",
            isSelected: false
        )
    }
    .padding()
    .frame(width: 500)
}

#Preview("Highlighted Text") {
    HighlightedText(
        text: "The main topic today is the Q2 pricing proposal. We need to decide on the three tiers.",
        highlight: "pricing"
    )
    .padding()
}

#Preview("No Results") {
    NoSearchResults(query: "xyzabc123")
        .frame(width: 500, height: 300)
}

#Preview("Search Header") {
    SearchResultsHeader(query: "pricing", resultCount: 12, onClose: {})
        .frame(width: 500)
}

#Preview("Keyboard Hints") {
    SearchKeyboardHints()
        .frame(width: 500)
}
