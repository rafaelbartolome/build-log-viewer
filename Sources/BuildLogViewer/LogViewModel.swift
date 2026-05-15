import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class LogViewModel {
    var document: LogDocument?
    var selectedFindingID: String?
    var selectedFinding: LogFinding?
    var searchQuery = ""
    var searchMatches: [LogSearchMatch] = []
    var activeSearchIndex: Int?
    var deduplicateWarnings = true
    var isLoading = false
    var errorMessage: String?
    var navigationRange: NSRange?
    var navigationToken = UUID()

    private var currentLoadTask: Task<Void, Never>?
    private var currentSearchTask: Task<Void, Never>?
    private var openedInitialArgument = false

    var activeSearchDescription: String {
        guard let activeSearchIndex else {
            return searchMatches.isEmpty ? "0" : "\(searchMatches.count)"
        }
        return "\(activeSearchIndex + 1) of \(searchMatches.count)"
    }

    var highlightedSearchRanges: [NSRange] {
        searchMatches.prefix(1_000).map(\.range)
    }

    var hasErrorFindings: Bool {
        !displayedFindings(for: .error).isEmpty
    }

    var errorNavigationDescription: String {
        let errors = displayedFindings(for: .error)
        guard !errors.isEmpty else {
            return "0"
        }

        guard let selectedFinding, selectedFinding.kind == .error,
              let selectedIndex = errors.firstIndex(where: { $0.id == selectedFinding.id }) else {
            return "\(errors.count)"
        }

        return "\(selectedIndex + 1) of \(errors.count)"
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        let logType = UTType(filenameExtension: "log") ?? .plainText
        panel.allowedContentTypes = [.plainText, .text, logType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.message = "Choose a CI build log."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        open(url: url)
    }

    func openInitialArgumentIfNeeded() {
        guard !openedInitialArgument else {
            return
        }
        openedInitialArgument = true

        guard let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
            return
        }

        open(url: URL(fileURLWithPath: path))
    }

    func open(url: URL) {
        currentLoadTask?.cancel()
        currentSearchTask?.cancel()
        isLoading = true
        errorMessage = nil
        document = nil
        selectedFindingID = nil
        selectedFinding = nil
        searchMatches = []
        activeSearchIndex = nil

        currentLoadTask = Task {
            do {
                let parsed = try await LogLoader.load(url: url)
                guard !Task.isCancelled else { return }

                document = parsed
                isLoading = false
                updateSearch()

                if let firstFailure = parsed.findings.first(where: { $0.kind == .buildFailure || $0.kind == .error }) {
                    select(finding: firstFailure)
                } else {
                    jumpToTop()
                }
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func displayedFindings(for kind: FindingKind) -> [LogFinding] {
        document?.findings(of: kind, deduplicateWarnings: deduplicateWarnings) ?? []
    }

    func selectFinding(id: String?) {
        guard let id else {
            selectedFinding = nil
            return
        }

        let visibleFindings = FindingKind.allCases.flatMap { displayedFindings(for: $0) }
        guard let finding = visibleFindings.first(where: { $0.id == id }) else {
            return
        }

        select(finding: finding)
    }

    func select(finding: LogFinding) {
        selectedFindingID = finding.id
        selectedFinding = finding
        activeSearchIndex = nil
        jumpToLine(finding.firstLineNumber)
    }

    func updateSearch() {
        currentSearchTask?.cancel()

        let query = searchQuery
        guard let document else {
            searchMatches = []
            activeSearchIndex = nil
            return
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchMatches = []
            activeSearchIndex = nil
            return
        }

        currentSearchTask = Task {
            let matches = await Task.detached(priority: .userInitiated) {
                document.search(query)
            }.value

            guard !Task.isCancelled else { return }
            searchMatches = matches
            activeSearchIndex = matches.isEmpty ? nil : 0

            if let first = matches.first {
                selectedFindingID = nil
                selectedFinding = nil
                jump(to: first.range)
            }
        }
    }

    func nextMatch() {
        guard !searchMatches.isEmpty else {
            return
        }

        let nextIndex = ((activeSearchIndex ?? -1) + 1) % searchMatches.count
        activateSearchMatch(at: nextIndex)
    }

    func previousMatch() {
        guard !searchMatches.isEmpty else {
            return
        }

        let current = activeSearchIndex ?? 0
        let previousIndex = (current - 1 + searchMatches.count) % searchMatches.count
        activateSearchMatch(at: previousIndex)
    }

    func nextError() {
        activateError(direction: 1)
    }

    func previousError() {
        activateError(direction: -1)
    }

    func jumpToLine(_ lineNumber: Int) {
        guard let range = document?.rangeForLine(lineNumber) else {
            return
        }

        jump(to: range)
    }

    private func activateSearchMatch(at index: Int) {
        guard searchMatches.indices.contains(index) else {
            return
        }

        activeSearchIndex = index
        selectedFindingID = nil
        selectedFinding = nil
        jump(to: searchMatches[index].range)
    }

    private func activateError(direction: Int) {
        let errors = displayedFindings(for: .error)
        guard !errors.isEmpty else {
            return
        }

        let targetIndex: Int
        if let selectedFinding, selectedFinding.kind == .error,
           let selectedIndex = errors.firstIndex(where: { $0.id == selectedFinding.id }) {
            targetIndex = (selectedIndex + direction + errors.count) % errors.count
        } else if let referenceLineNumber {
            targetIndex = errorIndex(relativeTo: referenceLineNumber, direction: direction, in: errors)
        } else {
            targetIndex = direction >= 0 ? 0 : errors.count - 1
        }

        select(finding: errors[targetIndex])
    }

    private var referenceLineNumber: Int? {
        if let selectedFinding {
            return selectedFinding.firstLineNumber
        }

        if let activeSearchIndex, searchMatches.indices.contains(activeSearchIndex) {
            return searchMatches[activeSearchIndex].lineNumber
        }

        return nil
    }

    private func errorIndex(relativeTo lineNumber: Int, direction: Int, in errors: [LogFinding]) -> Int {
        if direction >= 0 {
            return errors.firstIndex { $0.firstLineNumber > lineNumber } ?? 0
        }

        return errors.lastIndex { $0.firstLineNumber < lineNumber } ?? (errors.count - 1)
    }

    private func jumpToTop() {
        navigationRange = NSRange(location: 0, length: 0)
        navigationToken = UUID()
    }

    private func jump(to range: NSRange) {
        navigationRange = range
        navigationToken = UUID()
    }
}
