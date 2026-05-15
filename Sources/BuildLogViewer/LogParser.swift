import Foundation

enum LogParser {
    static func parse(data: Data, url: URL? = nil) -> LogDocument {
        let decoded = String(decoding: data, as: UTF8.self)
        return parse(text: decoded, rawByteCount: data.count, url: url)
    }

    static func parse(text rawText: String, rawByteCount: Int? = nil, url: URL? = nil) -> LogDocument {
        let stripped = stripTerminalSequences(from: rawText)
        let normalized = stripped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [LogLine] = []
        var findings: [LogFinding] = []
        var isInBuildFailureSummary = false
        lines.reserveCapacity(rawLines.count)

        for (index, rawLine) in rawLines.enumerated() {
            let line = String(rawLine)
            let lineNumber = index + 1
            let lowercased = line.lowercased()
            let isDisplayableLine = !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isBuildFailureSummaryLine = isInBuildFailureSummary || startsBuildFailureSummary(lowercased: lowercased)

            if isDisplayableLine {
                lines.append(LogLine(number: lineNumber, text: line))

                for kind in kinds(in: line, isBuildFailureSummaryLine: isBuildFailureSummaryLine) {
                    findings.append(LogFinding(kind: kind, lineNumber: lineNumber, summary: line.truncatedForSidebar))
                }
            }

            if startsBuildFailureSummary(lowercased: lowercased) {
                isInBuildFailureSummary = true
            } else if isInBuildFailureSummary, endsBuildFailureSummary(lowercased: lowercased) {
                isInBuildFailureSummary = false
            }
        }

        let text = lines.map(\.text).joined(separator: "\n")
        return LogDocument(
            url: url,
            rawByteCount: rawByteCount ?? rawText.utf8.count,
            lines: lines,
            findings: findings,
            text: text,
            lineStartOffsets: makeLineStartOffsets(for: lines),
            lineIndexByNumber: makeLineIndexByNumber(for: lines)
        )
    }

    static func stripTerminalSequences(from input: String) -> String {
        var output = String()
        output.reserveCapacity(input.count)

        let scalars = input.unicodeScalars
        var index = scalars.startIndex

        while index < scalars.endIndex {
            let scalar = scalars[index]

            if scalar.value == 0x1B {
                index = indexAfterEscapeSequence(startingAt: index, in: scalars)
                continue
            }

            if scalar.value == 0x07 {
                index = scalars.index(after: index)
                continue
            }

            output.unicodeScalars.append(scalar)
            index = scalars.index(after: index)
        }

        return output
    }

    private static func kinds(in line: String, isBuildFailureSummaryLine: Bool = false) -> [FindingKind] {
        let lowercased = line.lowercased()
        if containsWarningSymbol(line) {
            return [.warning]
        }

        var kinds: [FindingKind] = []
        let isBuildFailureLine = isBuildFailure(line: line, lowercased: lowercased) || isBuildFailureSummaryLine

        if isBuildFailureLine {
            kinds.append(.buildFailure)
        }

        if isFastlaneOrXcodeFailure(line: line, lowercased: lowercased) {
            kinds.append(.fastlane)
        }

        if isError(line: line, lowercased: lowercased, isBuildFailureLine: isBuildFailureLine) {
            kinds.append(.error)
        }

        if isWarning(line: line, lowercased: lowercased) {
            kinds.append(.warning)
        }

        return kinds
    }

    private static func isError(line: String, lowercased: String, isBuildFailureLine: Bool) -> Bool {
        isBuildFailureLine
            || line.contains("🚨 Error")
            || lowercased.contains("xcodebuild: error")
            || lowercased.contains("fatal error")
            || containsDiagnosticErrorMarker(in: line)
            || containsNonZeroExitStatus(lowercased: lowercased)
            || lowercased.contains("[!] error")
            || lowercased.contains("user command error")
    }

    private static func containsDiagnosticErrorMarker(in line: String) -> Bool {
        let displayLine = line.strippedForDisplay
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        if displayLine.range(of: #"^error:"#, options: [.caseInsensitive, .regularExpression]) != nil {
            return true
        }

        if displayLine.range(of: #"^\[[^\]]+\]:\s*error:"#, options: [.caseInsensitive, .regularExpression]) != nil {
            return true
        }

        return line.range(
            of: #":\d+(?::\d+)?:\s*error:"#,
            options: [.caseInsensitive, .regularExpression]
        ) != nil
    }

    private static func containsNonZeroExitStatus(lowercased: String) -> Bool {
        lowercased.range(
            of: #"exit status:\s*[1-9]\d*"#,
            options: .regularExpression
        ) != nil
    }

    private static func isWarning(line: String, lowercased: String) -> Bool {
        containsWarningSymbol(line)
            || lowercased.contains("warning:")
            || lowercased.contains(" warn ")
            || lowercased.hasPrefix("warn ")
            || lowercased.contains(" warning ")
    }

    private static func containsWarningSymbol(_ line: String) -> Bool {
        line.unicodeScalars.contains { $0.value == 0x26A0 }
    }

    private static func isBuildFailure(line: String, lowercased: String) -> Bool {
        line.contains("** TEST BUILD FAILED **")
            || line.contains("** BUILD FAILED **")
            || startsBuildFailureSummary(lowercased: lowercased)
            || lowercased.contains("testing failed")
            || lowercased.contains("command swiftcompile failed")
            || lowercased.contains("swiftcompile normal")
            || lowercased.contains("build failed")
            || endsBuildFailureSummary(lowercased: lowercased)
    }

    private static func startsBuildFailureSummary(lowercased: String) -> Bool {
        lowercased.contains("the following build commands failed")
    }

    private static func endsBuildFailureSummary(lowercased: String) -> Bool {
        lowercased.range(
            of: #"\(\d+\s+failures?\)"#,
            options: .regularExpression
        ) != nil
    }

    private static func isFastlaneOrXcodeFailure(line: String, lowercased: String) -> Bool {
        lowercased.contains("exit status:")
            || lowercased.contains("fastlane finished with errors")
            || lowercased.contains("called from fastfile")
            || lowercased.contains("error building/testing the application")
            || lowercased.contains("xcodebuild")
    }

    private static func makeLineStartOffsets(for lines: [LogLine]) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(lines.count)

        var currentOffset = 0
        for line in lines {
            offsets.append(currentOffset)
            currentOffset += (line.text as NSString).length + 1
        }

        return offsets
    }

    private static func makeLineIndexByNumber(for lines: [LogLine]) -> [Int: Int] {
        var indexes: [Int: Int] = [:]
        indexes.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            indexes[line.number] = index
        }

        return indexes
    }

    private static func indexAfterEscapeSequence(
        startingAt escapeIndex: String.UnicodeScalarView.Index,
        in scalars: String.UnicodeScalarView
    ) -> String.UnicodeScalarView.Index {
        let afterEscape = scalars.index(after: escapeIndex)
        guard afterEscape < scalars.endIndex else {
            return afterEscape
        }

        switch scalars[afterEscape].value {
        case 0x5B:
            return indexAfterControlSequenceIntroducer(startingAt: afterEscape, in: scalars)
        case 0x5D, 0x5F, 0x50, 0x5E:
            return indexAfterStringControlSequence(startingAt: afterEscape, in: scalars)
        default:
            return scalars.index(after: afterEscape)
        }
    }

    private static func indexAfterControlSequenceIntroducer(
        startingAt introducerIndex: String.UnicodeScalarView.Index,
        in scalars: String.UnicodeScalarView
    ) -> String.UnicodeScalarView.Index {
        var index = scalars.index(after: introducerIndex)

        while index < scalars.endIndex {
            let value = scalars[index].value
            let nextIndex = scalars.index(after: index)
            if (0x40...0x7E).contains(value) {
                return nextIndex
            }
            index = nextIndex
        }

        return index
    }

    private static func indexAfterStringControlSequence(
        startingAt introducerIndex: String.UnicodeScalarView.Index,
        in scalars: String.UnicodeScalarView
    ) -> String.UnicodeScalarView.Index {
        var index = scalars.index(after: introducerIndex)

        while index < scalars.endIndex {
            let value = scalars[index].value

            if value == 0x07 {
                return scalars.index(after: index)
            }

            if value == 0x1B {
                let afterEscape = scalars.index(after: index)
                if afterEscape < scalars.endIndex, scalars[afterEscape].value == 0x5C {
                    return scalars.index(after: afterEscape)
                }
            }

            index = scalars.index(after: index)
        }

        return index
    }
}
