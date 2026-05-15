import Foundation

enum FindingKind: String, CaseIterable, Identifiable, Sendable {
    case error
    case warning
    case buildFailure
    case fastlane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .error:
            "Errors"
        case .warning:
            "Warnings"
        case .buildFailure:
            "Build Failures"
        case .fastlane:
            "Fastlane/Xcode"
        }
    }

    var symbolName: String {
        switch self {
        case .error:
            "xmark.octagon.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .buildFailure:
            "hammer.fill"
        case .fastlane:
            "terminal.fill"
        }
    }
}

struct LogLine: Identifiable, Equatable, Sendable {
    let number: Int
    let text: String

    var id: Int { number }
}

struct LogFinding: Identifiable, Equatable, Sendable {
    let id: String
    let kind: FindingKind
    let firstLineNumber: Int
    let summary: String
    let occurrenceCount: Int
    let lineNumbers: [Int]

    init(kind: FindingKind, lineNumber: Int, summary: String, occurrenceCount: Int = 1, lineNumbers: [Int]? = nil) {
        self.kind = kind
        self.firstLineNumber = lineNumber
        self.summary = summary
        self.occurrenceCount = occurrenceCount
        self.lineNumbers = lineNumbers ?? [lineNumber]
        self.id = "\(kind.rawValue)-\(lineNumber)-\(summary.stableIdentifierHash)"
    }

    init(id: String, kind: FindingKind, firstLineNumber: Int, summary: String, occurrenceCount: Int, lineNumbers: [Int]) {
        self.id = id
        self.kind = kind
        self.firstLineNumber = firstLineNumber
        self.summary = summary
        self.occurrenceCount = occurrenceCount
        self.lineNumbers = lineNumbers
    }
}

struct LogSearchMatch: Identifiable, Equatable, Sendable {
    let index: Int
    let location: Int
    let length: Int
    let lineNumber: Int
    let preview: String

    var id: Int { index }
    var range: NSRange { NSRange(location: location, length: length) }
}

struct LogDocument: Sendable {
    let url: URL?
    let rawByteCount: Int
    let lines: [LogLine]
    let findings: [LogFinding]
    let text: String
    let lineStartOffsets: [Int]
    let lineIndexByNumber: [Int: Int]

    var lineCount: Int { lines.count }

    func findings(of kind: FindingKind, deduplicateWarnings: Bool) -> [LogFinding] {
        let matching = findings.filter { $0.kind == kind }
        guard kind == .warning, deduplicateWarnings else {
            return matching
        }

        var orderedKeys: [String] = []
        var grouped: [String: LogFinding] = [:]

        for finding in matching {
            let key = "\(finding.kind.rawValue)-\(finding.summary.normalizedFindingKey)"
            if let existing = grouped[key] {
                grouped[key] = LogFinding(
                    id: existing.id,
                    kind: existing.kind,
                    firstLineNumber: existing.firstLineNumber,
                    summary: existing.summary,
                    occurrenceCount: existing.occurrenceCount + finding.occurrenceCount,
                    lineNumbers: existing.lineNumbers + finding.lineNumbers
                )
            } else {
                orderedKeys.append(key)
                grouped[key] = LogFinding(
                    id: "dedup-\(finding.id)",
                    kind: finding.kind,
                    firstLineNumber: finding.firstLineNumber,
                    summary: finding.summary,
                    occurrenceCount: finding.occurrenceCount,
                    lineNumbers: finding.lineNumbers
                )
            }
        }

        return orderedKeys.compactMap { grouped[$0] }
    }

    func rangeForLine(_ lineNumber: Int) -> NSRange? {
        guard let index = lineIndexByNumber[lineNumber] else {
            return nil
        }

        guard lines.indices.contains(index), lineStartOffsets.indices.contains(index) else {
            return nil
        }

        return NSRange(
            location: lineStartOffsets[index],
            length: max(1, (lines[index].text as NSString).length)
        )
    }

    func contextLines(around lineNumber: Int, radius: Int = 2) -> [LogLine] {
        guard !lines.isEmpty else { return [] }
        let centerIndex = lineIndexByNumber[lineNumber] ?? nearestLineIndex(for: lineNumber)
        let lowerBound = max(0, centerIndex - radius)
        let upperBound = min(lines.count, centerIndex + radius + 1)
        return lines[lowerBound..<upperBound].map { $0 }
    }

    func search(_ query: String, limit: Int = 5_000) -> [LogSearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let nsText = text as NSString
        var matches: [LogSearchMatch] = []
        var searchRange = NSRange(location: 0, length: nsText.length)

        while matches.count < limit {
            let found = nsText.range(
                of: trimmed,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )

            guard found.location != NSNotFound else {
                break
            }

            let lineIndex = lineIndex(containingUTF16Offset: found.location)
            let line = lines.indices.contains(lineIndex) ? lines[lineIndex] : LogLine(number: 1, text: "")
            matches.append(
                LogSearchMatch(
                    index: matches.count,
                    location: found.location,
                    length: found.length,
                    lineNumber: line.number,
                    preview: line.text.truncatedForSidebar
                )
            )

            let nextLocation = found.location + max(found.length, 1)
            guard nextLocation < nsText.length else {
                break
            }

            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return matches
    }

    private func lineIndex(containingUTF16Offset offset: Int) -> Int {
        guard !lineStartOffsets.isEmpty else {
            return 0
        }

        var lowerBound = 0
        var upperBound = lineStartOffsets.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if lineStartOffsets[midpoint] <= offset {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return max(0, lowerBound - 1)
    }

    private func nearestLineIndex(for lineNumber: Int) -> Int {
        var lowerBound = 0
        var upperBound = lines.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if lines[midpoint].number < lineNumber {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return min(lowerBound, max(0, lines.count - 1))
    }
}

extension String {
    var strippedForDisplay: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "▸", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var truncatedForSidebar: String {
        let cleaned = strippedForDisplay
        guard cleaned.count > 180 else {
            return cleaned
        }

        let endIndex = cleaned.index(cleaned.startIndex, offsetBy: 180)
        return String(cleaned[..<endIndex]) + "..."
    }

    var normalizedFindingKey: String {
        strippedForDisplay
            .lowercased()
            .replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var stableIdentifierHash: String {
        let bytes = Array(utf8)
        let hash = bytes.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
